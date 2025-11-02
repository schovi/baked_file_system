# Baked File System

Include (bake them) static files into a binary at compile time and access them anytime you need.

## Installation


Add this to your application's `shard.yml`:

```yaml
dependencies:
  baked_file_system:
    github: schovi/baked_file_system
    version: 0.10.0
```

## Usage

Create a class that extends `BakedFileSystem` and use `bake_folder` to include static files at compile time.

```crystal
require "baked_file_system"

class Assets
  extend BakedFileSystem

  bake_folder "./public"
  bake_folder "./views", include_dotfiles: true
end
```

**Options:**
- `bake_folder(path, dir = __DIR__, allow_empty: false, include_dotfiles: false)` - Bake all files in a directory
- `include_dotfiles: true` - Include files/folders starting with `.` (e.g., `.gitignore`)
- `allow_empty: false` - Raise error if folder is empty

### Loading Files

```crystal
# Get file or raise BakedFileSystem::NoSuchFileError
file = Assets.get("path/to/file.txt")

# Get file or nil
file = Assets.get?("path/to/file.txt")

# Read file content as String
content = Assets.get("file.txt").gets_to_end

# List all baked files
Assets.files.each do |file|
  puts "#{file.path} (#{file.size} bytes)"
end
```

### File Properties

```crystal
file = Assets.get("document.pdf")

file.path          # => "/document.pdf"
file.size          # => 10240 (original uncompressed size)
file.compressed?   # => true (all files are automatically compressed)
file.compressed_size # => 3120 (actual stored size in binary)
```

### Compression

Files are automatically gzip-compressed at compile time to reduce binary size. This is transparent - reading a file automatically decompresses it.

**Special case:** Files ending in `.gz` are stored compressed as-is (no double compression).

```crystal
# Both work the same - automatic decompression on read
Assets.get("file.txt").gets_to_end
Assets.get("file.txt.gz").gets_to_end
```

### Advanced

Add files programmatically:

```crystal
class Assets
  extend BakedFileSystem

  bake_folder "./public"
  bake_file "/generated.json", %({"created": true})
end
```

Write file to IO with optional compression:

```crystal
file = Assets.get("document.pdf")

# Write decompressed content
file.write_to_io(io, compressed: false)

# Write original compressed content
file.write_to_io(io, compressed: true)
```

### Error Handling

```crystal
# Raise on missing file
begin
  Assets.get("missing/file")
rescue BakedFileSystem::NoSuchFileError
  puts "File not found"
end

# Or use safe access
unless file = Assets.get?("missing/file")
  puts "File not found"
end
```

## Benchmarks

Comprehensive benchmarking suite comparing BakedFileSystem against traditional File I/O. See [benchmarks/README.md](benchmarks/README.md) for detailed methodology and instructions.

### System Specifications

- **OS:** Darwin 25.0.0 (arm64) - Apple M4 Pro
- **Crystal:** 1.17.1
- **Test Date:** 2025-11-02

### Compile Time

Embedding ~1.2 MB of assets adds **3.7 seconds** to compilation time (30% overhead):

| Configuration   | Mean Compile Time |
|-----------------|-------------------|
| Baseline        | 12.27s            |
| BakedFileSystem | 15.98s            |

### Binary Size

Automatic gzip compression achieves **0.88x ratio** (assets compressed to 88% of original size):

| Metric      | Baseline | BakedFileSystem | Overhead  |
|-------------|----------|-----------------|-----------|
| Binary Size | 1.69 MB  | 2.72 MB         | +1.03 MB  |
| Assets      | -        | 1.17 MB (raw)   | -         |

### Memory Usage

Minimal startup overhead with lazy decompression:

| Stage             | Baseline | BakedFileSystem | Overhead |
|-------------------|----------|-----------------|----------|
| Startup           | 5.02 MB  | 5.08 MB         | +0.06 MB |
| After Small File  | 5.97 MB  | 5.20 MB         | -0.77 MB |
| After Medium File | 6.12 MB  | 5.77 MB         | -0.36 MB |
| After Large File  | 6.14 MB  | 10.38 MB        | +4.23 MB |

### Performance

Comparable latency and throughput (1000 requests, 10 concurrent clients):

| File Size | Baseline Latency | BakedFileSystem Latency | Throughput Baseline | Throughput Baked |
|-----------|------------------|-------------------------|---------------------|------------------|
| Small (1KB)   | 0.17 ms      | 0.17 ms                 | 56,034 req/s        | 55,790 req/s     |
| Medium (100KB) | 0.17 ms     | 0.17 ms                 | 56,588 req/s        | 55,457 req/s     |
| Large (1MB)   | 0.17 ms      | 0.17 ms                 | 56,575 req/s        | 54,922 req/s     |

### Summary

**Use BakedFileSystem when:**
- Deploying small to medium static assets (< 10 MB)
- Single-binary deployment is preferred
- Assets don't change frequently

**Benefits:**
- ✅ Single binary with embedded assets
- ✅ Automatic gzip compression (12% size reduction)
- ✅ Minimal memory overhead
- ✅ Comparable performance to file I/O

**Trade-offs:**
- ⚠️ +3.7s compilation time
- ⚠️ +1 MB binary size per 1 MB of assets
- ⚠️ Assets fixed at compile time

## Development

TODO: Write development instructions here

## Contributing

1. Fork it ( https://github.com/schovi/baked_file_system/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [schovi](https://github.com/schovi) David Schovanec
- [straight-shoota](https://github.com/straight-shoota) Johannes Müller
