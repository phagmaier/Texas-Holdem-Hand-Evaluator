const std = @import("std");
const Card = @import("card.zig");

const HIGH_CARD_BASE = 1;
const PAIR_BASE = 2;
const TWO_PAIR_BASE = 3;
const TRIPS_BASE = 4;
const STRAIGHT_BASE = 5;
const FLUSH_BASE = 6;
const FULL_HOUSE_BASE = 7;
const QUADS_BASE = 8;
const STRAIGHT_FLUSH_BASE = 9;

pub const Evaluator = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    flush_lookup: std.AutoHashMap(u16, u32),
    unsuited_lookup: std.AutoHashMap(u32, u32),

    pub fn init(allocator: std.mem.Allocator) !Self {
        var self = Self{
            .allocator = allocator,
            .flush_lookup = std.AutoHashMap(u16, u32).init(allocator),
            .unsuited_lookup = std.AutoHashMap(u32, u32).init(allocator),
        };

        try self.flush_lookup.ensureTotalCapacity(1287);
        try self.unsuited_lookup.ensureTotalCapacity(4900);
        try self.generateTables();

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.flush_lookup.deinit();
        self.unsuited_lookup.deinit();
    }

    pub fn handStrength(self: *Self, hand: [7]u32) u32 {
        var ranks: u16 = 0;
        var suit_ranks = [4]u16{ 0, 0, 0, 0 };
        var suit_counts = [4]u8{ 0, 0, 0, 0 };

        inline for (hand) |card| {
            const r = (card >> 8) & 0xF;
            const s = (card >> 12) & 0xF;

            const s_idx = switch (s) {
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

        inline for (suit_counts, 0..) |count, i| {
            if (count >= 5) {
                var flush_bits = suit_ranks[i];
                while (@popCount(flush_bits) > 5) {
                    const lowest_bit = flush_bits & (~flush_bits +% 1);
                    flush_bits ^= lowest_bit;
                }

                if (self.flush_lookup.get(flush_bits)) |val| {
                    if (val > STRAIGHT_BASE << 20) {
                        return val; // Straight Flush
                    }
                    return (FLUSH_BASE << 26) | val;
                }
                return (FLUSH_BASE << 26) | flush_bits;
            }
        }

        if (self.flush_lookup.get(ranks)) |val| {
            return (STRAIGHT_BASE << 26) | val;
        }

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

            const prod = p0 * p1 * p2 * p3 * p4;

            if (self.unsuited_lookup.get(prod)) |val| {
                if (val > max_val) max_val = val;
            }
        }

        return max_val;
    }

    fn generateTables(self: *Self) !void {
        const primes = Card.PRIMES;

        const straights = [_][5]u8{
            .{ 12, 0, 1, 2, 3 }, // 5-high
            .{ 0, 1, 2, 3, 4 },
            .{ 1, 2, 3, 4, 5 },
            .{ 2, 3, 4, 5, 6 },
            .{ 3, 4, 5, 6, 7 },
            .{ 4, 5, 6, 7, 8 },
            .{ 5, 6, 7, 8, 9 },
            .{ 6, 7, 8, 9, 10 },
            .{ 7, 8, 9, 10, 11 },
            .{ 8, 9, 10, 11, 12 },
        };

        for (straights, 0..) |s, i| {
            var mask: u16 = 0;
            for (s) |r| mask |= @as(u16, 1) << @intCast(r);
            const val = @as(u32, @intCast(i)) + 1;
            try self.flush_lookup.put(mask, (STRAIGHT_FLUSH_BASE << 26) | val);
        }

        var rank: u16 = 0;
        while (rank < (1 << 13)) : (rank += 1) {
            if (@popCount(rank) == 5) {
                if (!self.flush_lookup.contains(rank)) {
                    const val = evaluateFlushRank(rank);
                    try self.flush_lookup.put(rank, val);
                }
            }
        }

        try self.generateUnsuitedImpl(QUADS_BASE, 4, 1);
        try self.generateUnsuitedImpl(FULL_HOUSE_BASE, 3, 2);

        for (0..13) |q| {
            for (0..13) |k| {
                if (q == k) continue;
                const prod = primes[q] * primes[q] * primes[q] * primes[q] * primes[k];
                const val = (QUADS_BASE << 26) | (@as(u32, @intCast(q)) << 13) | @as(u32, @intCast(k));
                try self.unsuited_lookup.put(prod, val);
            }
        }

        for (0..13) |t| {
            for (0..13) |p| {
                if (t == p) continue;
                const prod = primes[t] * primes[t] * primes[t] * primes[p] * primes[p];
                const val = (FULL_HOUSE_BASE << 26) | (@as(u32, @intCast(t)) << 13) | @as(u32, @intCast(p));
                try self.unsuited_lookup.put(prod, val);
            }
        }

        for (0..13) |t| {
            for (0..13) |k1| {
                if (k1 == t) continue;
                for (0..13) |k2| {
                    if (k2 == t or k2 == k1) continue;
                    const prod = primes[t] * primes[t] * primes[t] * primes[k1] * primes[k2];
                    const val = (TRIPS_BASE << 26) | (@as(u32, @intCast(t)) << 13);
                    try self.unsuited_lookup.put(prod, val);
                }
            }
        }

        for (0..13) |p1| {
            for (0..13) |p2| {
                if (p1 == p2) continue;
                for (0..13) |k| {
                    if (k == p1 or k == p2) continue;
                    const prod = primes[p1] * primes[p1] * primes[p2] * primes[p2] * primes[k];
                    const val = (TWO_PAIR_BASE << 26) | (@as(u32, @intCast(p1)) << 13);
                    try self.unsuited_lookup.put(prod, val);
                }
            }
        }

        for (0..13) |p| {
            for (0..13) |k1| {
                if (k1 == p) continue;
                for (0..13) |k2| {
                    if (k2 == p or k2 == k1) continue;
                    for (0..13) |k3| {
                        if (k3 == p or k3 == k1 or k3 == k2) continue;
                        const prod = primes[p] * primes[p] * primes[k1] * primes[k2] * primes[k3];
                        const val = (PAIR_BASE << 26) | (@as(u32, @intCast(p)) << 13);
                        try self.unsuited_lookup.put(prod, val);
                    }
                }
            }
        }

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
                                const val = (HIGH_CARD_BASE << 26) | calculateHighCardVal(i, j, k, l, m);
                                try self.unsuited_lookup.put(prod, val);
                            }
                        }
                    }
                }
            }
        }
    }

    fn isStraight(i: u8, j: u8, k: u8, l: u8, m: u8) bool {
        if (m == l + 1 and l == k + 1 and k == j + 1 and j == i + 1) return true;
        if (m == 12 and i == 0 and j == 1 and k == 2 and l == 3) return true;
        return false;
    }

    fn evaluateFlushRank(rank: u16) u32 {
        return rank;
    }

    fn calculateHighCardVal(i: u8, j: u8, k: u8, l: u8, m: u8) u32 {
        var val: u32 = 0;
        val |= @as(u32, 1) << @intCast(i);
        val |= @as(u32, 1) << @intCast(j);
        val |= @as(u32, 1) << @intCast(k);
        val |= @as(u32, 1) << @intCast(l);
        val |= @as(u32, 1) << @intCast(m);
        return val;
    }
};

test "Make Evaluator" {
    var da = std.heap.DebugAllocator(.{}){};
    const allocator = da.allocator();
    defer _ = da.deinit();
    var eval = try Evaluator.init(allocator);
    defer eval.deinit();
}
