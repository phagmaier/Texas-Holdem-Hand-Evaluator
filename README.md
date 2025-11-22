# Zig Poker Hand Evaluator

A high-performance poker hand evaluator written in Zig, optimized for maximum throughput using prime number encoding and direct memory lookups.

## Overview

This evaluator is designed for heavy-duty poker analysis (solvers, equity calculators, and simulations). It determines the exact strength of poker hands using a combination of prime number products and bit manipulation.

It supports **7-card evaluation** (Texas Hold'em style) out of the box, automatically finding the best 5-card combination among the 21 possible permutations.

## 🚀 Performance

This library trades memory for raw speed. By allocating large direct-access tables (\~420MB), it avoids hashing overhead entirely, achieving state-of-the-art evaluation speeds on consumer hardware.

**Benchmark Results (7-Card Evaluation):**

| Metric | Result |
|:---|:---|
| **Throughput** | **\~15.1 Million hands/sec** |
| **Latency** | \~66 nanoseconds per hand |
| **Thread** | Single-threaded |

**Test Environment:**

  * **Device:** Laptop 13 (Framework)
  * **CPU:** AMD Ryzen 7 7840U (Zen 4) @ 3.30 GHz
  * **RAM:** 16 GB LPDDR5
  * **Build Mode:** `ReleaseFast`

## Features

  - **True O(1) Lookup**: Uses direct array indexing for instant hand evaluation. No hash collisions, no binary search.
  - **7-Card Native**: Optimized specifically for Texas Hold'em evaluation (7 choose 5).
  - **Complete Hand Rankings**: Supports all standard poker hands from High Card to Royal Flush.
  - **Tie-Breaker Accuracy**: Distinction between hands of the same rank (e.g., King-High Flush vs. Queen-High Flush).

## How It Works

### 1\. Prime Number Encoding

Each card rank is assigned a unique prime number (Two=2, ..., Ace=41). The product of five cards' prime numbers uniquely identifies rank-based hands (Pairs, Trips, Full Houses) regardless of suit.

### 2\. Direct Memory Lookup ("The Nuclear Option")

Instead of using HashMaps (which incur hashing overhead) or Binary Search (which incurs branching overhead), this evaluator allocates a flat array of \~105 million integers (\~420MB RAM). The prime product of a hand is used as the **direct index** into this array to fetch the hand strength instantly.

### 3\. Evaluation Strategy

1.  **Flush Check**: Bitwise operations check if 5+ cards share a suit. If so, a 65KB lookup table determines the strength.
2.  **Straight Check**: Bitmasks check for sequential rank patterns.
3.  **Rainbow/Unsuited**: If no flush or straight is found, the prime product of the cards is calculated and used to index the main 420MB lookup table.

## Usage

```zig
const std = @import("std");
const Evaluator = @import("evaluator.zig").Evaluator;
const Card = @import("card.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize evaluator.
    // WARNING: Allocates ~420MB of RAM for lookup tables.
    var evaluator = try Evaluator.init(allocator);
    defer evaluator.deinit();

    // Evaluate a 7-card hand
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
    
    // Higher values = better hands
    std.debug.print("Hand strength: {}\n", .{strength});
}
```

## Build & Run

* To achieve the stated performance metrics, you **must** build with optimizations enabled. Debug builds include safety checks that significantly slow down bitwise operations.

```bash
# Run the benchmark/main example
zig build run -Doptimize=ReleaseFast

# Run the test suite
zig build test
```

## API Reference

### `Evaluator.init(allocator)`

Allocates \~420MB for lookup tables and populates them. This takes a split second on modern CPUs but is memory intensive.

### `evaluator.handStrength(cards: [7]u32)`

The hot path. Calculates the strength of the best 5-card hand formed from the 7 input cards.

  * **Input:** Array of 7 encoded integers.
  * **Output:** `u32` representing absolute hand strength.

## Hand Strength Encoding

The returned `u32` strength is structured to allow direct integer comparison:

  - **Bits 26-31:** Hand Category (High Card=1 ... Straight Flush=9)
  - **Bits 0-25:** Tiebreaker value (Specific to the hand category)

## License

This project is MIT-licensed. Feel free to explore, modify, and use it in your own solvers.
