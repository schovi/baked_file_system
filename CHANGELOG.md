# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.12.0] - 2025-11-03

### Added
- Compile-time size validation and warnings for embedded files
- `Stats` class to track total and per-file compressed sizes
- `ByteCounter` IO wrapper for accurate size tracking during encoding
- Environment variable support for global size limits:
  - `BAKED_FILE_SYSTEM_MAX_SIZE` - Maximum total compressed size (default: 50MB)
  - `BAKED_FILE_SYSTEM_WARN_THRESHOLD` - Warning threshold for total size (default: 10MB)
- `max_size` parameter for `bake_folder` macro to set per-folder limits
- Automatic warnings for large individual files (>1MB compressed)
- Comprehensive examples demonstrating size validation features
- Detailed size reporting during compilation (file count, compression ratio)

### Changed
- **BREAKING**: Builds will now fail at compile-time if embedded files exceed 50MB compressed (configurable)
- Size statistics are now always displayed during compilation

### Migration Guide

If your build fails with a size limit error after upgrading:

**Quick temporary fix (environment variable):**
```bash
# Set to your required size in bytes (e.g., 100MB)
BAKED_FILE_SYSTEM_MAX_SIZE=104857600 crystal build your_app.cr
```

**Recommended fix (per-folder limit):**
```crystal
module Assets
  extend BakedFileSystem

  # Set max_size to your required limit (in bytes)
  bake_folder "./assets", max_size: 104_857_600  # 100MB
end
```

**Why this change?**
This feature prevents accidental inclusion of huge files that bloat binary size. The default 50MB limit is generous for most use cases. You can configure limits per-project via environment variables or per-folder via the `max_size` parameter.

**Error message example:**
```
❌  ERROR: Total embedded size (75.2 MB) exceeds limit (50.0 MB)
    Reduce the number/size of embedded files or increase the limit.
```

### Documentation
- Added "Size Management & Limits" section to README
- New `examples/` directory with working demonstrations
- Comprehensive test coverage for size validation features

## [0.11.0] - 2025-06-06

### Added
- `include_dotfiles` option for `bake_folder` to support dot files and folders
- Enhanced documentation with more examples

### Fixed
- Windows compatibility issues with path handling
- Empty directory handling on Windows

## [0.10.0] - 2021-04-15

### Removed
- **BREAKING**: Removed `BakedFile#mime_type` method (use `MIME.from_filename()` from Crystal stdlib instead)

### Changed
- Improved cross-platform compatibility

## Previous Versions

For changes in versions 0.9.x and earlier, see git history.

[0.12.0]: https://github.com/schovi/baked_file_system/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/schovi/baked_file_system/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/schovi/baked_file_system/compare/v0.9.8...v0.10.0
