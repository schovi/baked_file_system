# BakedFileSystem Examples

This directory contains examples demonstrating BakedFileSystem's size validation and warning features.

## Directory Structure

```
examples/
├── README.md              # This file
├── .gitignore            # Ignores compiled binaries
├── warning_example.cr     # Shows size warnings (compiles successfully)
├── threshold_example.cr   # Exceeds max_size limit (compilation fails)
└── assets/                # Test files for embedding
    ├── small.txt      # 10KB (compresses to ~55 bytes)
    ├── medium.bin     # 50KB (compresses to ~50KB)
    └── large.bin      # 100KB (compresses to ~100KB)
```

## Test Files

The assets directory contains small, git-friendly test files that demonstrate size validation:

- **small.txt**: 10KB of zeros (highly compressible → ~55 bytes)
- **medium.bin**: 50KB of random data (doesn't compress → ~50KB)
- **large.bin**: 100KB of random data (doesn't compress → ~100KB)
- **Total**: ~160KB uncompressed → ~150KB compressed

These small files are intentionally chosen to be reasonable for git while still demonstrating all validation features.

## Examples

### 1. Warning Example (Successful Compilation)

This example embeds files and shows statistics, with optional warnings via environment variables.

**Basic run (no warnings):**
```bash
cd examples
crystal build warning_example.cr
```

**Expected output:**
```
BakedFileSystem: Embedded 3 files (160.0 KB → 153.8 KB compressed, 96.1% ratio)
```

**Run with warnings enabled:**
```bash
# Set threshold low enough to trigger warnings
BAKED_FILE_SYSTEM_WARN_THRESHOLD=30000 crystal build warning_example.cr
```

**Expected output with warnings:**
```
BakedFileSystem: Embedded 3 files (160.0 KB → 153.8 KB compressed, 96.1% ratio)

⚠️  WARNING: Total embedded size (153.8 KB) is significant.
    Consider using lazy loading or external storage for large assets.
```

**Then run the compiled binary:**
```bash
./warning_example
```

**You'll see:**
```
Successfully embedded 3 files!

Embedded files:
  /small.txt: 10.0 KB
  /medium.bin: 50.0 KB
  /large.bin: 100.0 KB

Accessing a file:
  Path: /small.txt
  Size: 10240 bytes
  First 50 bytes (hex): <hex data>
```

### 2. Threshold Example (Compilation Fails)

This example sets a strict `max_size` limit that the assets exceed, causing compilation to fail.

**Run:**
```bash
cd examples
crystal build threshold_example.cr
```

**Expected output (compilation failure):**
```
BakedFileSystem: Embedded 3 files (160.0 KB → 153.8 KB compressed, 96.1% ratio)

❌  ERROR: Total embedded size (153.8 KB) exceeds limit (50.0 KB)
    Reduce the number/size of embedded files or increase the limit.

Error: execution of command failed with code: 1: <loader path>
```

**Note:** The binary will not be created because compilation fails.

## Using Environment Variables

You can control size limits via environment variables:

```bash
# Set maximum total size (default: 50 MB)
export BAKED_FILE_SYSTEM_MAX_SIZE=200000  # 200 KB

# Set warning threshold (default: 10 MB)
export BAKED_FILE_SYSTEM_WARN_THRESHOLD=30000  # 30 KB

# Now compile with these limits
crystal build warning_example.cr
```

**This demonstrates:**
- Warnings appear when total size exceeds `BAKED_FILE_SYSTEM_WARN_THRESHOLD`
- Compilation fails when total size exceeds `BAKED_FILE_SYSTEM_MAX_SIZE`
- Default limits are production-friendly (50 MB max, 10 MB warning)
- Limits can be adjusted per-project or per-folder

## Key Concepts

### Size Reporting
- **Always shown** during compilation
- Shows file count, raw size, compressed size, and compression ratio
- Helps you understand binary size impact
- No performance overhead - happens at compile time only

### Warnings (Non-Fatal)
- **Large File Warning**: Individual files >1 MB compressed (default)
- **Significant Size Warning**: Total size exceeds `BAKED_FILE_SYSTEM_WARN_THRESHOLD` (default: 10 MB)
- Warnings don't stop compilation - they're informational
- Can be adjusted via environment variables for testing

### Errors (Fatal)
- **Size Limit Exceeded**: Total compressed size exceeds `max_size` parameter or `BAKED_FILE_SYSTEM_MAX_SIZE`
- Stops compilation with clear error message
- Default limit: 50 MB (can be overridden)
- Prevents accidentally huge binaries

## Configuration Examples

**Per-folder limit:**
```crystal
module Assets
  extend BakedFileSystem
  bake_folder path: "./images", max_size: 10_485_760  # 10MB limit
end
```

**Global limit via environment:**
```bash
# In your build script or CI environment
export BAKED_FILE_SYSTEM_MAX_SIZE=104857600  # 100MB
crystal build your_app.cr
```

**Disable warnings (keep limits):**
```bash
# Set warning threshold very high
export BAKED_FILE_SYSTEM_WARN_THRESHOLD=999999999
crystal build your_app.cr
```

## Cleaning Up

To remove the compiled binaries:

```bash
# From examples directory
rm -f warning_example threshold_example

# Or use git clean
git clean -fdx
```

## Learn More

See the main [README.md](../README.md) for complete documentation on:
- Using BakedFileSystem in your projects
- Configuration options
- Performance characteristics
- Best practices
- Benchmarking results
