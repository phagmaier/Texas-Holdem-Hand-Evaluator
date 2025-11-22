const std = @import("std");
const Evaluator = @import("evaluator.zig").Evaluator;
const Card = @import("card.zig");
const print = std.debug.print;
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var eval = try Evaluator.init(allocator);

    const NUM_HANDS = 10_000_000;
    print("Generating {d} hands for benchmark...\n", .{NUM_HANDS});

    const hands = try allocator.alloc([7]u32, NUM_HANDS);

    var prng = std.Random.DefaultPrng.init(0x12345678);
    const random = prng.random();

    const deck = Card.makeDeck(); // Assuming you have this
    for (hands) |*hand| {
        for (0..7) |i| {
            hand[i] = deck[random.uintLessThan(usize, 52)];
        }
    }

    print("Starting benchmark...\n", .{});
    var timer = try std.time.Timer.start();

    var total_score: u64 = 0;

    for (hands) |hand| {
        const score = eval.handStrength(hand);
        total_score += score;
    }

    const ns = timer.read();

    const seconds = @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
    const hands_per_sec = @as(f64, @floatFromInt(NUM_HANDS)) / seconds;

    print("Evaluated {d} hands in {d:.4} seconds\n", .{ NUM_HANDS, seconds });
    print("Speed: {d:.2} million hands/sec\n", .{hands_per_sec / 1_000_000.0});
    print("just printing this so that it doesn't remove loop: {d}\n", .{total_score});
}
