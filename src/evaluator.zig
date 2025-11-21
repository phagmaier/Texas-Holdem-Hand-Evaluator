const std = @import("std");
const Card = @import("card.zig");

const HIGH_CARD = 0;
const PAIR = 1;
const TWO_PAIR = 2;
const TRIPS = 3;
const STRAIGHT = 4;
const FLUSH = 5;
const FULL_HOUSE = 6;
const QUADS = 7;
const STRAIGHT_FLUSH = 8;

pub const Evaluator = struct {
    const PERMS = [21][5]u8{
        .{ 0, 1, 2, 3, 4 }, .{ 0, 1, 2, 3, 5 }, .{ 0, 1, 2, 3, 6 },
        .{ 0, 1, 2, 4, 5 }, .{ 0, 1, 2, 4, 6 }, .{ 0, 1, 2, 5, 6 },
        .{ 0, 1, 3, 4, 5 }, .{ 0, 1, 3, 4, 6 }, .{ 0, 1, 3, 5, 6 },
        .{ 0, 1, 4, 5, 6 }, .{ 0, 2, 3, 4, 5 }, .{ 0, 2, 3, 4, 6 },
        .{ 0, 2, 3, 5, 6 }, .{ 0, 2, 4, 5, 6 }, .{ 0, 3, 4, 5, 6 },
        .{ 1, 2, 3, 4, 5 }, .{ 1, 2, 3, 4, 6 }, .{ 1, 2, 3, 5, 6 },
        .{ 1, 2, 4, 5, 6 }, .{ 1, 3, 4, 5, 6 }, .{ 2, 3, 4, 5, 6 },
    };
    lookup: std.AutoHashMap(u32, u32),
    flush_lookup: std.AutoHashMap(u16, u32),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Evaluator {
        var self = Evaluator{
            .lookup = std.AutoHashMap(u32, u32).init(allocator),
            .flush_lookup = std.AutoHashMap(u16, u32).init(allocator),
            .allocator = allocator,
        };
        try self.generate_tables();
        return self;
    }

    pub fn deinit(self: *Evaluator) void {
        self.lookup.deinit();
        self.flush_lookup.deinit();
    }

    pub fn handStrength(self: *Evaluator, cards: [7]u32) u32 {
        var max_val: u32 = 0;

        inline for (PERMS) |p| {
            const val = self.eval(cards[p[0]], cards[p[1]], cards[p[2]], cards[p[3]], cards[p[4]]);
            if (val > max_val) max_val = val;
        }

        return max_val;
    }

    pub fn eval(self: *Evaluator, c1: u32, c2: u32, c3: u32, c4: u32, c5: u32) u32 {
        if ((c1 & c2 & c3 & c4 & c5 & 0xF000) != 0) {
            var bit_rank: u16 = 0;
            bit_rank |= @as(u16, 1) << @intCast((c1 >> 8) & 0xF);
            bit_rank |= @as(u16, 1) << @intCast((c2 >> 8) & 0xF);
            bit_rank |= @as(u16, 1) << @intCast((c3 >> 8) & 0xF);
            bit_rank |= @as(u16, 1) << @intCast((c4 >> 8) & 0xF);
            bit_rank |= @as(u16, 1) << @intCast((c5 >> 8) & 0xF);

            if (self.flush_lookup.get(bit_rank)) |val| {
                return (STRAIGHT_FLUSH << 26) | val;
            }
            return (FLUSH << 26) | bit_rank;
        }

        const p1 = c1 & 0xFF;
        const p2 = c2 & 0xFF;
        const p3 = c3 & 0xFF;
        const p4 = c4 & 0xFF;
        const p5 = c5 & 0xFF;
        const product = p1 * p2 * p3 * p4 * p5;

        if (self.lookup.get(product)) |val| {
            return val;
        }

        var bit_rank: u32 = 0;
        bit_rank |= @as(u32, 1) << @intCast((c1 >> 8) & 0xF);
        bit_rank |= @as(u32, 1) << @intCast((c2 >> 8) & 0xF);
        bit_rank |= @as(u32, 1) << @intCast((c3 >> 8) & 0xF);
        bit_rank |= @as(u32, 1) << @intCast((c4 >> 8) & 0xF);
        bit_rank |= @as(u32, 1) << @intCast((c5 >> 8) & 0xF);
        return (HIGH_CARD << 26) | bit_rank;
    }

    fn generate_tables(self: *Evaluator) !void {
        const primes = Card.PRIMES;

        const straights = [_][5]u8{
            .{ 12, 0, 1, 2, 3 },
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
            var prod: u32 = 1;
            var mask: u16 = 0;
            for (s) |rank| {
                prod *= primes[rank];
                mask |= @as(u16, 1) << @intCast(rank);
            }
            try self.lookup.put(prod, (STRAIGHT << 26) | (@as(u32, @intCast(i)) + 1));
            try self.flush_lookup.put(mask, @as(u32, @intCast(i)) + 1);
        }

        for (0..13) |quad| {
            for (0..13) |kicker| {
                if (quad == kicker) continue;
                const p = primes[quad];
                const k = primes[kicker];
                const prod = p * p * p * p * k;
                const val = (QUADS << 26) | (@as(u32, @intCast(quad)) << 13) | @as(u32, @intCast(kicker));
                try self.lookup.put(prod, val);
            }
        }

        for (0..13) |trip| {
            for (0..13) |pair| {
                if (trip == pair) continue;
                const t = primes[trip];
                const p = primes[pair];
                const prod = t * t * t * p * p;
                const val = (FULL_HOUSE << 26) | (@as(u32, @intCast(trip)) << 13) | @as(u32, @intCast(pair));
                try self.lookup.put(prod, val);
            }
        }

        for (0..13) |trip| {
            for (0..13) |k1| {
                if (k1 == trip) continue;
                for (0..13) |k2| {
                    if (k2 == trip or k2 == k1) continue;
                    const t = primes[trip];
                    const prod = t * t * t * primes[k1] * primes[k2];

                    var kickers: u32 = 0;
                    kickers |= @as(u32, 1) << @intCast(k1);
                    kickers |= @as(u32, 1) << @intCast(k2);

                    const val = (TRIPS << 26) | (@as(u32, @intCast(trip)) << 13) | kickers;
                    try self.lookup.put(prod, val);
                }
            }
        }

        for (0..13) |p1| {
            for (0..13) |p2| {
                if (p1 == p2) continue;
                for (0..13) |k| {
                    if (k == p1 or k == p2) continue;
                    const prod = primes[p1] * primes[p1] * primes[p2] * primes[p2] * primes[k];

                    const pair_val = if (p1 > p2) (@as(u32, @intCast(p1)) << 13) | @as(u32, @intCast(p2)) else (@as(u32, @intCast(p2)) << 13) | @as(u32, @intCast(p1));

                    const val = (TWO_PAIR << 26) | pair_val | (@as(u32, 1) << @intCast(k));
                    try self.lookup.put(prod, val);
                }
            }
        }

        for (0..13) |pair| {
            for (0..13) |k1| {
                if (k1 == pair) continue;
                for (0..13) |k2| {
                    if (k2 == pair or k2 == k1) continue;
                    for (0..13) |k3| {
                        if (k3 == pair or k3 == k1 or k3 == k2) continue;
                        const prod = primes[pair] * primes[pair] * primes[k1] * primes[k2] * primes[k3];

                        var kickers: u32 = 0;
                        kickers |= @as(u32, 1) << @intCast(k1);
                        kickers |= @as(u32, 1) << @intCast(k2);
                        kickers |= @as(u32, 1) << @intCast(k3);

                        const val = (PAIR << 26) | (@as(u32, @intCast(pair)) << 13) | kickers;
                        try self.lookup.put(prod, val);
                    }
                }
            }
        }
    }
};
