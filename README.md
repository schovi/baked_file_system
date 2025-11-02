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
