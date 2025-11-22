const std = @import("std");
const Card = @import("card.zig");

const STRAIGHT_FLUSH = 1;
const FOUR_OF_A_KIND = 2;
const FULL_HOUSE = 3;
const FLUSH = 4;
const STRAIGHT = 5;
const THREE_OF_A_KIND = 6;
const TWO_PAIR = 7;
const PAIR = 8;
const HIGH_CARD = 9;

pub const Evaluator = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    flush_lookup: std.AutoHashMap(u16, u32),
    unsuited_lookup: std.AutoHashMap(u32, u32),

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        self.allocator = allocator;
        self.flush_lookup = std.AutoHashMap(u16, u32).init(allocator);
        self.unsuited_lookup = std.AutoHashMap(u32, u32).init(allocator);
        try self.flush_lookup.ensureTotalCapacity(1287);
        try self.unsuited_lookup.ensureTotalCapacity(6175);
        try generateTables(self);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.flush_lookup.deinit();
        self.unsuited_lookup.deinit();
        self.allocator.destroy(self);
    }

    pub fn handStrength(self: *Evaluator, hand: [7]u32) u32 {
        var ranks: u16 = 0;
        var suit_ranks = [4]u16{ 0, 0, 0, 0 };
        var suit_count = [4]u8{ 0, 0, 0, 0 };

        inline for (hand) |card| {
            const rank = Card.getRankInt(card);
            const suit = Card.getSuitInt(card);
            ranks |= rank;
            suit_ranks[suit] |= rank;
            suit_count[suit] += 1;
        }

        inline for (suit_count, 0..) |count, i| {
            if (count >= 5) {
                const bit_rank = suit_ranks[i];
                // Check straight flush first (faster lookup)
                if (self.flush_lookup.get(bit_rank)) |value| {
                    if (value <= 10) {
                        return (STRAIGHT_FLUSH << 26) | bit_rank;
                    }
                    return (FLUSH << 26) | bit_rank;
                }
                return (FLUSH << 26) | bit_rank;
            }
        }

        if (self.flush_lookup.get(ranks)) |_| {
            return (STRAIGHT << 26) | ranks;
        }

        const prime_product = self.primeProductFromRankbits(ranks);
        if (self.unsuited_lookup.get(prime_product)) |value| {
            return value;
        }

        return (HIGH_CARD << 26) | ranks;
    }

    fn primeProductFromRankbits(self: *Evaluator, rankbits: u16) u32 {
        _ = self;
        var product: u32 = 1;
        var bits = rankbits;
        var i: u5 = 0;

        while (bits != 0) : (i += 1) {
            if ((bits & 1) != 0) {
                product *= Card.PRIMES[i];
            }
            bits >>= 1;
        }
        return product;
    }
};

fn generateTables(evaluator: *Evaluator) !void {
    try generateFlushLookup(evaluator);
    try generateUnsuitedLookup(evaluator);
}

fn generateFlushLookup(evaluator: *Evaluator) !void {
    const straight_flushes = [_]u16{
        0b1111100000000,
        0b0111110000000,
        0b0011111000000,
        0b0001111100000,
        0b0000111110000,
        0b0000011111000,
        0b0000001111100,
        0b0000000111110,
        0b0000000011111,
        0b1000000001111,
    };

    for (straight_flushes, 0..) |sf, i| {
        try evaluator.flush_lookup.put(sf, @intCast(i + 1));
    }

    var rank: u16 = 0;
    while (rank < (1 << 13)) : (rank += 1) {
        if (@popCount(rank) == 5) {
            if (!evaluator.flush_lookup.contains(rank)) {
                const value = evaluateFlush(rank);
                try evaluator.flush_lookup.put(rank, value);
            }
        }
    }
}

fn evaluateFlush(ranks: u16) u32 {
    var value: u32 = 0;
    var bits = ranks;
    var shift: u5 = 0;

    while (bits != 0) {
        if (bits & 0x1000 != 0) { // Check MSB
            value |= @as(u32, 0x1000) >> shift;
            shift += 1;
        }
        bits <<= 1;
    }
    return value;
}

fn generateUnsuitedLookup(evaluator: *Evaluator) !void {
    const allocator = evaluator.allocator;

    var hands = try std.ArrayList([5]u8).initCapacity(allocator, 6175);
    defer hands.deinit();

    var i: u8 = 0;
    while (i < 13) : (i += 1) {
        var j: u8 = i;
        while (j < 13) : (j += 1) {
            var k: u8 = j;
            while (k < 13) : (k += 1) {
                var l: u8 = k;
                while (l < 13) : (l += 1) {
                    var m: u8 = l;
                    while (m < 13) : (m += 1) {
                        try hands.append([5]u8{ i, j, k, l, m });
                    }
                }
            }
        }
    }

    for (hands.items) |hand| {
        const prime_product = computePrimeProduct(hand);
        const value = evaluateHand(hand);
        try evaluator.unsuited_lookup.put(prime_product, value);
    }
}

inline fn computePrimeProduct(hand: [5]u8) u32 {
    var product: u32 = 1;
    inline for (hand) |rank| {
        product *= Card.PRIMES[rank];
    }
    return product;
}

fn evaluateHand(hand: [5]u8) u32 {
    var rank_counts = [_]u8{0} ** 13;

    inline for (hand) |rank| {
        rank_counts[rank] += 1;
    }

    var four_rank: ?usize = null;
    var three_rank: ?usize = null;
    var pair1: ?usize = null;
    var pair2: ?usize = null;

    for (rank_counts, 0..) |count, rank| {
        switch (count) {
            4 => four_rank = rank,
            3 => three_rank = rank,
            2 => {
                if (pair1 == null) {
                    pair1 = rank;
                } else {
                    pair2 = rank;
                }
            },
            else => {},
        }
    }

    if (four_rank) |rank| {
        return (FOUR_OF_A_KIND << 26) | (@as(u32, 1) << @intCast(rank));
    }

    if (three_rank != null and pair1 != null) {
        return (FULL_HOUSE << 26) | (@as(u32, 1) << @intCast(three_rank.?));
    }

    if (three_rank) |rank| {
        return (THREE_OF_A_KIND << 26) | (@as(u32, 1) << @intCast(rank));
    }

    if (pair1 != null and pair2 != null) {
        return (TWO_PAIR << 26) | (@as(u32, 1) << @intCast(pair1.?)) | (@as(u32, 1) << @intCast(pair2.?));
    }

    if (pair1) |rank| {
        return (PAIR << 26) | (@as(u32, 1) << @intCast(rank));
    }

    var ranks: u32 = 0;
    inline for (hand) |rank| {
        ranks |= @as(u32, 1) << @intCast(rank);
    }
    return (HIGH_CARD << 26) | ranks;
}

test "Make sure solver works" {}
