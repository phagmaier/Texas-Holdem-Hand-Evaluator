# Poker Hand Evaluator (Zig)

A fast and efficient poker hand evaluator written in Zig that uses lookup tables and prime number encoding for optimal performance.

## Overview

This evaluator can determine the strength of poker hands using a combination of prime number products and bit manipulation. It evaluates all standard poker hands from high card to straight flush and can handle both 5-card and 7-card hands (like Texas Hold'em).

## Features

- **Fast Evaluation**: Uses pre-computed lookup tables for O(1) hand evaluation
- **7-Card Support**: Automatically evaluates all 21 possible 5-card combinations from 7 cards
- **Complete Hand Rankings**: Supports all standard poker hands:
  - High Card
  - One Pair
  - Two Pair
  - Three of a Kind (Trips)
  - Straight
  - Flush
  - Full House
  - Four of a Kind (Quads)
  - Straight Flush

## How It Works

### Prime Number Encoding

Each card rank is assigned a unique prime number. The product of five cards' prime numbers uniquely identifies most hand patterns (pairs, trips, quads, full houses, two pair).

### Bit Manipulation

- Cards are encoded with suit information in bits 12-15
- Rank information in bits 8-11
- Prime number value in bits 0-7

### Evaluation Strategy

1. **Flush Detection**: Check if all 5 cards share a suit using bitwise AND
2. **Straight/Straight Flush**: Use bit masks for rank patterns
3. **Made Hands**: Use prime products to look up pairs, trips, quads, and full houses
4. **High Card**: Fall back to bit rank representation

## Usage

```zig
const std = @import("std");
const Evaluator = @import("evaluator.zig").Evaluator;
const Card = @import("card.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize evaluator (builds lookup tables)
    var evaluator = try Evaluator.init(allocator);
    defer evaluator.deinit();

    // Evaluate a 7-card hand (e.g., Texas Hold'em)
    const hand = [7]u32{
        Card.encode(.Ace, .Spades),
        Card.encode(.King, .Spades),
        Card.encode(.Queen, .Spades),
        Card.encode(.Jack, .Spades),
        Card.encode(.Ten, .Spades),
        Card.encode(.Two, .Hearts),
        Card.encode(.Three, .Clubs),
    };
    
    const strength = evaluator.handStrength(hand);
    
    // Higher values are better hands
    std.debug.print("Hand strength: {}\n", .{strength});
}
```

## API

### `Evaluator.init(allocator: std.mem.Allocator)`
Initializes the evaluator and generates lookup tables. Must be called before evaluation.

### `Evaluator.deinit()`
Cleans up allocated memory.

### `evaluator.handStrength(cards: [7]u32) u32`
Evaluates a 7-card hand by checking all 21 possible 5-card combinations.
Returns the maximum hand strength value (higher = better).

### `evaluator.eval(c1, c2, c3, c4, c5: u32) u32`
Evaluates exactly 5 cards and returns the hand strength value.

## Hand Strength Encoding

The returned strength value is encoded as:
- Bits 26-31: Hand type (0-8)
- Bits 0-25: Tiebreaker information (varies by hand type)

This ensures that stronger hands always have higher values and proper tiebreaking within the same hand type.

## Dependencies

Requires a `card.zig` module that defines:
- `Card.PRIMES`: Array of prime numbers for each rank
- Card encoding functions

## Performance

The evaluator uses pre-computed lookup tables for constant-time evaluation of most hands. Initial table generation takes ~O(n³) time but only happens once during initialization.

## License

This project is MIT-licensed. Feel free to explore, modify, and build upon it.
