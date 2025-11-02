# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Baked File System** is a Crystal language library that embeds static files into compiled binaries at compile time, allowing zero-cost access to files at runtime. Files are automatically gzip-compressed to minimize binary size.

**Key capabilities:**
- Embed entire folders or individual files into a binary via compile-time macros
- Automatic gzip compression with transparent decompression on read
- Support for dotfiles/hidden files via `include_dotfiles` option
- File metadata (path, size, compressed status)
- Safe file access with `.get()` and `.get?()` methods

## Build & Test Commands

### Install dependencies
```bash
shards install
```

### Run all tests
```bash
crystal spec
```

### Run a specific test file
```bash
crystal spec spec/baked_file_system_spec.cr
```

### Run tests matching a pattern
```bash
crystal spec spec/baked_file_system_spec.cr --pattern "load only files"
```

### Compile a check (without running tests)
```bash
crystal build src/baked_file_system.cr
```

### Build the loader executable (used internally)
```bash
crystal build src/loader.cr -o loader
```

## Architecture & Key Components

### Compile-time & Runtime Flow

1. **Compile-Time (User's Code)**
   - User extends `BakedFileSystem` in their code and calls `bake_folder` macro
   - This triggers the `BakedFileSystem.bake_folder()` macro in `src/baked_file_system.cr:178`
   - The macro invokes the loader process via `run()` directive

2. **Loader Process** (`src/loader/`)
   - A separate Crystal program (`src/loader.cr`) receives folder path and options
   - `BakedFileSystem::Loader.load()` (`src/loader/loader.cr`) scans the directory
   - Uses `Dir.glob()` with optional `DotFiles` flag to find files
   - For each file:
     - Reads raw bytes
     - Compresses with gzip (unless file ends in `.gz`)
     - Encodes binary data as escaped string via `StringEncoder`
     - Generates Crystal code that creates `BakedFile` objects
   - Output is generated back to the calling compile process

3. **Generated Code Integration**
   - The generated Crystal code is macro-expanded into the user's binary
   - Creates `BakedFile` instances added to `@@files` class variable
   - User code can now call `.get()`, `.get?()`, `.files` on their class

4. **Runtime Access**
   - `BakedFile` extends `IO` for stream-like reading
   - Automatically decompresses gzip on read unless `compressed?` is true
   - Path normalization ensures consistent "/" prefixes

### Main Classes & Modules

- **`BakedFileSystem::BakedFile`** (`src/baked_file_system.cr:39`): Represents a virtual file, extends `IO`, handles decompression on read
- **`BakedFileSystem::NoSuchFileError`** (`src/baked_file_system.cr:25`): Exception for missing files
- **`BakedFileSystem::Loader`** (`src/loader/loader.cr`): Compile-time file scanning and encoding engine
- **`StringEncoder`** (`src/loader/string_encoder.cr`): Encodes binary data as escaped Crystal string literals

### Key Macros

- **`bake_folder(path, dir, allow_empty, include_dotfiles)`** (`src/baked_file_system.cr:178`): Embeds all files from a directory
  - Runs loader process to generate file embedding code
  - Can raise if folder is empty (controlled by `allow_empty`)
  - When `include_dotfiles: true`, includes files/folders starting with "."

- **`bake_file(path, content)`** (`src/baked_file_system.cr:196`): Manually adds a single file with string content

## Important Implementation Details

### Compression & Storage (`src/baked_file_system.cr`)

- All files are stored compressed in the binary (in `@slice`)
- Files ending in `.gz` are stored as-is (no double compression)
- `BakedFile#compressed?` indicates if data is pre-compressed
- On read, non-compressed data passes through `Compress::Gzip::Reader` automatically
- Memory usage is minimal: each file is a lazy IO wrapper around embedded byte slice

### String Encoding (`src/loader/string_encoder.cr`)

- Encodes binary data as escaped string literals for embedding in Crystal code
- Critical for compile-time macro code generation
- Handles proper escaping of special characters

### File Discovery (`src/loader/loader.cr:26`)

- Uses `Dir.glob()` with `Path.to_posix()` for cross-platform paths
- Respects `File::MatchOptions::DotFiles` flag
- Rejects directories, only includes files

## Test Structure

- **`spec/baked_file_system_spec.cr`**: Main test suite for file access, compression, and error handling
- **`spec/loader_spec.cr`**: Tests for the loader executable
- **`spec/string_encoder_spec.cr`**: Tests for string encoding logic
- **`spec/storage/`**: Test files to be baked (images, text, etc.)
- **`spec/empty_storage/`**: Empty directory for testing `allow_empty` validation

## Common Development Tasks

**Adding a new feature to `BakedFile`:**
1. Modify `BakedFile` class in `src/baked_file_system.cr`
2. Add test in `spec/baked_file_system_spec.cr`
3. Run `crystal spec` to validate

**Modifying the loader logic:**
1. Update `src/loader/loader.cr` or `src/loader/string_encoder.cr`
2. Add/update tests in `spec/loader_spec.cr` or `spec/string_encoder_spec.cr`
3. Test with `crystal spec`

**Cross-platform compatibility:**
- Use `Path.to_posix()` for consistent path handling
- Test on Windows, macOS, and Linux (CI runs on all three)
- Be aware that `File::Info`, `Dir.glob`, and path separators differ by OS

## CI/CD

GitHub Actions workflow (`.github/workflows/`) runs tests on:
- Ubuntu (latest and nightly Crystal)
- macOS (latest Crystal)
- Windows (latest Crystal)

All tests must pass on all platforms before merge.
