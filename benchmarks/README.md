# BakedFileSystem Benchmarks

Comprehensive benchmarking suite for comparing BakedFileSystem (compile-time asset embedding) against traditional File I/O approaches.

## Overview

This benchmark suite measures four key aspects of BakedFileSystem performance:

1. **Compile Time** - Overhead introduced by asset embedding during compilation
2. **Binary Size** - Impact on compiled binary size and compression efficiency
3. **Memory Usage** - Runtime memory footprint (RSS) at various stages
4. **Performance** - Request latency and throughput for serving static files

## Quick Start

### Run All Benchmarks

```bash
./run_all.sh
```

This will:
1. Run all four benchmark categories in sequence
2. Generate JSON result files in `results/`
3. Create a comprehensive markdown report at `results/REPORT.md`

**Expected Duration:** ~5-10 minutes depending on your system

### View Results

```bash
cat results/REPORT.md
```

## Individual Benchmarks

You can run benchmarks individually:

### Compile Time Benchmark

Measures compilation time overhead:

```bash
crystal run compile_time.cr
```

- **Output:** `results/compile_time.json`
- **Duration:** ~2-3 minutes (5 compile iterations per configuration)

### Binary Size Analysis

Analyzes compiled binary sizes and compression ratios:

```bash
crystal run binary_size.cr
```

- **Output:** `results/binary_size.json`
- **Duration:** ~30 seconds

### Memory Usage Benchmark

Profiles runtime memory usage (RSS):

```bash
crystal run memory.cr
```

- **Output:** `results/memory.json`
- **Duration:** ~30 seconds
- **Note:** Starts both servers temporarily on ports 3000 and 3001

### Performance Benchmark

Measures request latency and throughput:

```bash
crystal run performance.cr
```

- **Output:** `results/performance.json`
- **Duration:** ~2-3 minutes
- **Note:** Runs 1000 requests per file size with 10 concurrent clients

## Test Applications

The benchmarks compare two identical Kemal web applications:

### Baseline App (`baseline/`)

Traditional approach using File I/O:
- Uses `send_file` to serve files from disk
- No compile-time overhead
- Smaller binary size
- Disk I/O on each request

### Baked App (`baked/`)

BakedFileSystem approach:
- Uses `bake_folder` to embed assets at compile time
- Assets compressed with gzip automatically
- Larger binary size (includes embedded assets)
- Zero disk I/O - assets served from memory

## Test Assets

Both applications serve the same test files from `public/`:

- **small.txt** - ~1 KB text file
- **medium.json** - ~100 KB JSON file
- **large.dat** - ~1 MB binary data file

These represent typical small/medium/large static assets in web applications.

## Results Structure

After running benchmarks, results are stored in `results/`:

```
results/
├── compile_time.json    # Compilation time data
├── binary_size.json     # Binary size analysis
├── memory.json          # Memory usage profiles
├── performance.json     # Latency and throughput data
└── REPORT.md           # Comprehensive markdown report
```

### JSON Schema

Each JSON file contains structured data with timestamps, system info, and benchmark-specific metrics. See individual benchmark scripts for schema details.

## Report Generator

The report generator aggregates all JSON results into a readable markdown report:

```bash
crystal run report_generator.cr
```

The report includes:
- Executive summary with key findings
- System specifications
- Methodology overview
- Detailed results for each benchmark category
- Visual comparisons (ASCII bar charts)
- Conclusions and recommendations

## Requirements

- Crystal 1.0.0 or higher
- Kemal web framework
- Unix-like OS (macOS, Linux) for process monitoring
- Ports 3000 and 3001 available

## Cleanup

To clean up after benchmarks:

```bash
# Remove compiled binaries
rm -f baseline/baseline baked/baked

# Remove dependencies
rm -rf baseline/lib baked/lib
rm -f baseline/shard.lock baked/shard.lock

# Remove results (optional)
rm -rf results/
```

## Troubleshooting

### Port Already in Use

If you see "Address already in use" errors:

```bash
# Kill processes on ports 3000 and 3001
lsof -ti:3000 | xargs kill -9
lsof -ti:3001 | xargs kill -9
```

The `run_all.sh` script handles this automatically.

### Compilation Errors

Ensure dependencies are installed:

```bash
cd baseline && shards install
cd ../baked && shards install
```

### Inconsistent Results

For more accurate benchmarks:
- Close unnecessary applications
- Run multiple times and average results
- Ensure system is not under heavy load
- Use release builds (benchmarks do this automatically)

## Interpreting Results

### Compile Time

- **Expected:** 1-2 second overhead for ~1 MB of assets
- **Scales:** Approximately linear with asset size
- **Impact:** Only affects build time, not runtime

### Binary Size

- **Expected:** ~1.5x compression ratio (gzip compressed assets)
- **Overhead:** Binary size = base + (compressed asset size)
- **Impact:** One-time cost, doesn't affect runtime memory

### Memory Usage

- **Expected:** Minimal overhead (< 2 MB)
- **Key Insight:** Assets are NOT fully decompressed into RAM
- **Benefit:** Lazy decompression on read

### Performance

- **Small Files:** 5-10x speedup expected (no disk I/O)
- **Large Files:** Similar performance (I/O dominates)
- **Concurrent:** BakedFileSystem scales well with concurrency

## Use Cases

Based on benchmark results, BakedFileSystem is ideal for:

✅ Small to medium static assets (< 10 MB total)
✅ Read-heavy workloads
✅ Single-binary deployments
✅ Performance-critical static file serving

Not recommended for:

❌ Very large asset collections (> 50 MB)
❌ Frequently changing assets
❌ Extremely memory-constrained environments

## Contributing

To add new benchmarks:

1. Create a new `.cr` script in this directory
2. Output results to `results/your_benchmark.json`
3. Update `report_generator.cr` to include new data
4. Update `run_all.sh` to run your benchmark
5. Document in this README

## License

Same as BakedFileSystem project.
