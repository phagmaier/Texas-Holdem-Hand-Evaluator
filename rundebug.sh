#!/bin/bash
zig build 
cd zig-out/bin/
./benchmark
