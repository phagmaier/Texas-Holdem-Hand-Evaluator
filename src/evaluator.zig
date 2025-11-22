const std = @import("std");
const Card = @import("card.zig");

const HIGH_CARD_BASE: u32 = 1;
const PAIR_BASE: u32 = 2;
const TWO_PAIR_BASE: u32 = 3;
const TRIPS_BASE: u32 = 4;
const STRAIGHT_BASE: u32 = 5;
const FLUSH_BASE: u32 = 6;
const FULL_HOUSE_BASE: u32 = 7;
const FOUR_OF_A_KIND_BASE: u32 = 8;
const STRAIGHT_FLUSH_BASE: u32 = 9;

// 16K slots for ~6165 items -> load ≈ 0.37. Fits comfortably in L2 on modern CPUs.
const TABLE_SIZE: usize = 16 * 1024;
const TABLE_MASK: usize = TABLE_SIZE - 1;

// Compile-time assertion that TABLE_SIZE is a power of two
comptime {
    if ((TABLE_SIZE & (TABLE_SIZE - 1)) != 0) {
        @compileError("TABLE_SIZE must be a power of two");
    }
}

//sentinel: key == 0 means empty. Prime-products are never zero.
const Entry = packed struct {
    key: u32,
    val: u32,
};

const TABLES = generateTables();

pub const Evaluator = struct {
    const Self = @This();

    pub fn init() !Self {
        return Self{};
    }

    pub fn deinit(_: *Self) void {}

    pub fn handStrength(_: *const Self, hand: [7]u32) u32 {
        var ranks: u16 = 0;
        var suit_ranks = [4]u16{ 0, 0, 0, 0 };
        var suit_counts = [4]u8{ 0, 0, 0, 0 };

        inline for (hand) |card| {
            const r = @as(u32, @intCast((card >> 8) & 0xF));
            const s = (card >> 12) & 0xF;
            const s_idx: u32 = switch (s) {
                1 => 0,
                2 => 1,
                4 => 2,
                8 => 3,
                else => 0,
            };
            const bit = @as(u16, 1) << @intCast(r);
            ranks |= bit;
            suit_ranks[s_idx] |= bit;
            suit_counts[s_idx] += 1;
        }

        // Flush check
        inline for (suit_counts, 0..) |count, i| {
            if (count >= 5) {
                var flush_bits = suit_ranks[i];
                while (@popCount(flush_bits) > 5) {
                    const lowest_bit = flush_bits & (~flush_bits +% 1);
                    flush_bits ^= lowest_bit;
                }
                const val = TABLES.flushes[flush_bits];
                if (val != 0) {
                    if (val > STRAIGHT_BASE << 20) return val;
                    return (FLUSH_BASE << 26) | val;
                }
                return (FLUSH_BASE << 26) | flush_bits;
            }
        }

        // Straight check
        const straights = [_]u16{
            0b1111100000000, 0b0111110000000, 0b0011111000000, 0b0001111100000,
            0b0000111110000, 0b0000011111000, 0b0000001111100, 0b0000000111110,
            0b0000000011111, 0b1000000001111,
        };
        inline for (straights, 0..) |mask, i| {
            if ((ranks & mask) == mask) {
                return (STRAIGHT_BASE << 26) | @as(u32, @intCast(10 - i));
            }
        }

        // Evaluate remaining hands by checking all 5-card perms
        var max_val: u32 = 0;
        const PERMS = [21][5]u8{
            .{ 0, 1, 2, 3, 4 }, .{ 0, 1, 2, 3, 5 }, .{ 0, 1, 2, 3, 6 },
            .{ 0, 1, 2, 4, 5 }, .{ 0, 1, 2, 4, 6 }, .{ 0, 1, 2, 5, 6 },
            .{ 0, 1, 3, 4, 5 }, .{ 0, 1, 3, 4, 6 }, .{ 0, 1, 3, 5, 6 },
            .{ 0, 1, 4, 5, 6 }, .{ 0, 2, 3, 4, 5 }, .{ 0, 2, 3, 4, 6 },
            .{ 0, 2, 3, 5, 6 }, .{ 0, 2, 4, 5, 6 }, .{ 0, 3, 4, 5, 6 },
            .{ 1, 2, 3, 4, 5 }, .{ 1, 2, 3, 4, 6 }, .{ 1, 2, 3, 5, 6 },
            .{ 1, 2, 4, 5, 6 }, .{ 1, 3, 4, 5, 6 }, .{ 2, 3, 4, 5, 6 },
        };

        inline for (PERMS) |p| {
            const p0 = hand[p[0]] & 0xFF;
            const p1 = hand[p[1]] & 0xFF;
            const p2 = hand[p[2]] & 0xFF;
            const p3 = hand[p[3]] & 0xFF;
            const p4 = hand[p[4]] & 0xFF;

            const prod = @as(u32, p0 * p1 * p2 * p3 * p4);

            // mix the key then mask (fast, cheap)
            var idx: usize = @as(u32, @intCast(mix32(prod))) & @as(u32, @intCast(TABLE_MASK));
            // linear probe
            while (true) {
                const entry = TABLES.unsuited[idx];
                if (entry.key == prod) {
                    if (entry.val > max_val) max_val = entry.val;
                    break;
                }
                if (entry.key == 0) break; // empty slot -> not present
                idx = (idx + 1) & TABLE_MASK;
            }
        }

        return max_val;
    }
};

const TableData = struct {
    flushes: [65536]u32,
    unsuited: [TABLE_SIZE]Entry,
};

// Helper inserter with probe-limit to fail at compile-time if TABLE too small
fn insertComptime(table: *[TABLE_SIZE]Entry, prod: u32, val: u32) void {
    //var start = mix32(prod);
    //var idx: usize = @intCast(usize, start & @as(u32, TABLE_MASK));
    var idx: usize = @as(usize, @intCast(mix32(prod))) & @as(u32, @intCast(TABLE_MASK));
    var probes: usize = 0;
    while (probes < TABLE_SIZE) : (probes += 1) {
        if (table[idx].key == 0) {
            table[idx] = .{ .key = prod, .val = val };
            return;
        }
        if (table[idx].key == prod) return; // already present
        idx = (idx + 1) & TABLE_MASK;
    }
    @compileError("Hash table overflow in generateTables(); increase TABLE_SIZE");
}

fn generateTables() TableData {
    // Increase branch quota because this function does extensive comptime loops
    @setEvalBranchQuota(10_000_000);

    var data: TableData = undefined;

    // zero tables
    for (&data.flushes) |*f| f.* = 0;
    for (&data.unsuited) |*e| {
        e.key = 0;
        e.val = 0;
    }

    // straight-flush / flush table population
    const straights_arr = [_][5]u8{
        .{ 12, 0, 1, 2, 3 },   .{ 0, 1, 2, 3, 4 },  .{ 1, 2, 3, 4, 5 },
        .{ 2, 3, 4, 5, 6 },    .{ 3, 4, 5, 6, 7 },  .{ 4, 5, 6, 7, 8 },
        .{ 5, 6, 7, 8, 9 },    .{ 6, 7, 8, 9, 10 }, .{ 7, 8, 9, 10, 11 },
        .{ 8, 9, 10, 11, 12 },
    };
    for (straights_arr, 0..) |s, i| {
        var mask: u16 = 0;
        for (s) |r| mask |= @as(u16, 1) << @intCast(r);
        const val = @as(u32, @intCast(i)) + 1;
        data.flushes[mask] = (STRAIGHT_FLUSH_BASE << 26) | val;
    }
    var rank: u16 = 0;
    while (rank < (1 << 13)) : (rank += 1) {
        if (@popCount(rank) == 5) {
            if (data.flushes[rank] == 0) data.flushes[rank] = rank;
        }
    }

    const primes = Card.PRIMES;

    // Four of a kind
    for (0..13) |q| {
        for (0..13) |k| {
            if (q == k) continue;
            const prod = primes[q] * primes[q] * primes[q] * primes[q] * primes[k];
            const val = (FOUR_OF_A_KIND_BASE << 26) | (@as(u32, @intCast(q)) << 13) | @as(u32, @intCast(k));
            insertComptime(&data.unsuited, prod, val);
        }
    }

    // Full house
    for (0..13) |t| {
        for (0..13) |p| {
            if (t == p) continue;
            const prod = primes[t] * primes[t] * primes[t] * primes[p] * primes[p];
            const val = (FULL_HOUSE_BASE << 26) | (@as(u32, @intCast(t)) << 13) | @as(u32, @intCast(p));
            insertComptime(&data.unsuited, prod, val);
        }
    }

    // Trips
    for (0..13) |t| {
        for (0..13) |k1| {
            if (k1 == t) continue;
            for (0..13) |k2| {
                if (k2 == t or k2 == k1) continue;
                const prod = primes[t] * primes[t] * primes[t] * primes[k1] * primes[k2];
                var k_val: u32 = 0;
                if (k1 > k2) {
                    k_val = (@as(u32, @intCast(k1)) << 4) | @as(u32, @intCast(k2));
                } else {
                    k_val = (@as(u32, @intCast(k2)) << 4) | @as(u32, @intCast(k1));
                }
                const val = (TRIPS_BASE << 26) | (@as(u32, @intCast(t)) << 13) | k_val;
                insertComptime(&data.unsuited, prod, val);
            }
        }
    }

    // Two-pair
    for (0..13) |p1| {
        for (0..13) |p2| {
            if (p1 == p2) continue;
            for (0..13) |k| {
                if (k == p1 or k == p2) continue;
                const prod = primes[p1] * primes[p1] * primes[p2] * primes[p2] * primes[k];
                var pair_val: u32 = 0;
                if (p1 > p2) {
                    pair_val = (@as(u32, @intCast(p1)) << 13) | (@as(u32, @intCast(p2)) << 9);
                } else {
                    pair_val = (@as(u32, @intCast(p2)) << 13) | (@as(u32, @intCast(p1)) << 9);
                }
                const val = (TWO_PAIR_BASE << 26) | pair_val | @as(u32, @intCast(k));
                insertComptime(&data.unsuited, prod, val);
            }
        }
    }

    // Pair
    for (0..13) |p| {
        for (0..13) |k1| {
            if (k1 == p) continue;
            for (0..13) |k2| {
                if (k2 == p or k2 == k1) continue;
                for (0..13) |k3| {
                    if (k3 == p or k3 == k1 or k3 == k2) continue;
                    const prod = primes[p] * primes[p] * primes[k1] * primes[k2] * primes[k3];
                    var k_mask: u32 = 0;
                    k_mask |= @as(u32, 1) << @intCast(k1);
                    k_mask |= @as(u32, 1) << @intCast(k2);
                    k_mask |= @as(u32, 1) << @intCast(k3);
                    const val = (PAIR_BASE << 26) | (@as(u32, @intCast(p)) << 13) | k_mask;
                    insertComptime(&data.unsuited, prod, val);
                }
            }
        }
    }

    // High card (all 5-card combos that are not straights)
    var i: u8 = 0;
    while (i < 13) : (i += 1) {
        var j: u8 = i + 1;
        while (j < 13) : (j += 1) {
            var k: u8 = j + 1;
            while (k < 13) : (k += 1) {
                var l: u8 = k + 1;
                while (l < 13) : (l += 1) {
                    var m: u8 = l + 1;
                    while (m < 13) : (m += 1) {
                        if (!isStraight(i, j, k, l, m)) {
                            const prod = primes[i] * primes[j] * primes[k] * primes[l] * primes[m];
                            var val: u32 = 0;
                            val |= @as(u32, 1) << @intCast(i);
                            val |= @as(u32, 1) << @intCast(j);
                            val |= @as(u32, 1) << @intCast(k);
                            val |= @as(u32, 1) << @intCast(l);
                            val |= @as(u32, 1) << @intCast(m);
                            insertComptime(&data.unsuited, prod, (HIGH_CARD_BASE << 26) | val);
                        }
                    }
                }
            }
        }
    }

    return data;
}

fn isStraight(i: u8, j: u8, k: u8, l: u8, m: u8) bool {
    if (m == l + 1 and l == k + 1 and k == j + 1 and j == i + 1) return true;
    if (m == 12 and i == 0 and j == 1 and k == 2 and l == 3) return true; // wheel
    return false;
}

// cheap 32-bit mix function to decorrelate products before masking.
// fast and effective for multiplicative keys like prime products.
fn mix32(x: u32) u32 {
    var z: u32 = x;
    z = z ^ (z >> 16);
    z = z *% 0x7feb352d; // odd constant (wrapping multiply)
    z = z ^ (z >> 15);
    z = z *% 0x846ca68b; // wrapping multiply
    z = z ^ (z >> 16);
    return z;
}

test "Poker Hand Correctness" {
    var eval = try Evaluator.init();

    const royal = [_]u32{ Card.makeCard(12, 0), Card.makeCard(11, 0), Card.makeCard(10, 0), Card.makeCard(9, 0), Card.makeCard(8, 0), Card.makeCard(2, 1), Card.makeCard(3, 2) };

    const s_flush = [_]u32{ Card.makeCard(9, 0), Card.makeCard(8, 0), Card.makeCard(7, 0), Card.makeCard(6, 0), Card.makeCard(5, 0), Card.makeCard(12, 1), Card.makeCard(12, 2) };

    try std.testing.expect(eval.handStrength(royal) > eval.handStrength(s_flush));

    const quads = [_]u32{ Card.makeCard(5, 0), Card.makeCard(5, 1), Card.makeCard(5, 2), Card.makeCard(5, 3), Card.makeCard(12, 0), Card.makeCard(2, 0), Card.makeCard(3, 0) };
    const boat = [_]u32{ Card.makeCard(12, 0), Card.makeCard(12, 1), Card.makeCard(12, 2), Card.makeCard(11, 0), Card.makeCard(11, 1), Card.makeCard(2, 0), Card.makeCard(3, 0) };

    try std.testing.expect(eval.handStrength(quads) > eval.handStrength(boat));

    const wheel = [_]u32{ Card.makeCard(12, 0), Card.makeCard(0, 1), Card.makeCard(1, 2), Card.makeCard(2, 3), Card.makeCard(3, 0), Card.makeCard(11, 1), Card.makeCard(11, 2) };
    const pair_aces = [_]u32{ Card.makeCard(12, 0), Card.makeCard(12, 1), Card.makeCard(8, 2), Card.makeCard(7, 3), Card.makeCard(4, 0), Card.makeCard(2, 1), Card.makeCard(2, 2) };

    try std.testing.expect(eval.handStrength(wheel) > eval.handStrength(pair_aces));

    const board = [_]u32{ Card.makeCard(11, 0), Card.makeCard(11, 1), Card.makeCard(6, 2), Card.makeCard(6, 3), Card.makeCard(2, 0) };

    var p1_hand: [7]u32 = undefined;
    @memcpy(p1_hand[0..5], board[0..]);
    p1_hand[5] = Card.makeCard(12, 1); // Ace
    p1_hand[6] = Card.makeCard(0, 1); // 2

    var p2_hand: [7]u32 = undefined;
    @memcpy(p2_hand[0..5], board[0..]);
    p2_hand[5] = Card.makeCard(10, 1); // Queen
    p2_hand[6] = Card.makeCard(0, 2); // 2

    try std.testing.expect(eval.handStrength(p1_hand) > eval.handStrength(p2_hand));
}
