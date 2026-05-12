require "base64"
require "compress/gzip"
require "digest/sha256"
require "./string_encoder"
require "./stats"
require "./byte_counter"

module BakedFileSystem
  module Loader
    class Error < Exception
    end

    # Converts a glob pattern to a regular expression
    # Supports: * (any chars), ** (recursive dirs), ? (single char)
    private def self.glob_to_regex(pattern : String) : Regex
      # Escape regex special chars except glob wildcards
      escaped = pattern.gsub(/([.+^$(){}[\]|\\])/, "\\\\\\1")

      # Convert glob patterns to regex
      # Use placeholders to prevent ** patterns from being affected by * replacement
      # Handle ** (recursive directories) - must match zero or more path segments

      # Replace **/ with placeholder (e.g., "**/file.txt" should match "file.txt" and "a/b/file.txt")
      escaped = escaped.gsub("**/", "<<<DOUBLESTAR_SLASH>>>")

      # Replace /** with placeholder (e.g., "test/**" should match "test/file" and "test/a/b/file")
      escaped = escaped.gsub("/**", "<<<SLASH_DOUBLESTAR>>>")

      # Handle remaining * (any characters except path separator)
      escaped = escaped.gsub("*", "[^/]*")

      # Handle ? (single character except path separator)
      escaped = escaped.gsub("?", "[^/]")

      # Now replace placeholders with actual regex patterns
      # **/ means "zero or more directory levels followed by /" OR just ""
      escaped = escaped.gsub("<<<DOUBLESTAR_SLASH>>>", "(?:(?:[^/]+/)*)?")

      # /** means "/" followed by anything OR just ""
      escaped = escaped.gsub("<<<SLASH_DOUBLESTAR>>>", "(?:/.*)?")

      # Anchor the pattern to match full path
      Regex.new("^#{escaped}$")
    end

    # Checks if a file path matches a glob pattern
    # Patterns are matched against posix-style paths (using / separator)
    def self.matches_pattern?(file : String, pattern : String) : Bool
      # Normalize both file and pattern to use forward slashes
      normalized_file = file.gsub("\\", "/")
      normalized_pattern = pattern.gsub("\\", "/")

      # Remove leading slash from file if present for consistent matching
      normalized_file = normalized_file.lchop('/')
      normalized_pattern = normalized_pattern.lchop('/')

      regex = glob_to_regex(normalized_pattern)
      !regex.match(normalized_file).nil?
    end

    # Filters a list of files based on include and exclude patterns
    # If include patterns are provided, only files matching at least one include pattern are kept
    # Then, files matching any exclude pattern are removed
    # Returns filtered array of file paths
    def self.filter_files(files : Array(String), include_patterns : Array(String)?, exclude_patterns : Array(String)?) : Array(String)
      result = files

      # Apply include filters first - if specified, keep only matching files
      if include_patterns && !include_patterns.empty?
        result = result.select do |file|
          include_patterns.any? { |pattern| matches_pattern?(file, pattern) }
        end
      end

      # Apply exclude filters - remove any matching files
      if exclude_patterns && !exclude_patterns.empty?
        result = result.reject do |file|
          exclude_patterns.any? { |pattern| matches_pattern?(file, pattern) }
        end
      end

      result
    end

    def self.load(io, root_path, include_dotfiles = false, include_patterns : Array(String)? = nil, exclude_patterns : Array(String)? = nil, max_size : Int64? = nil, compress = true)
      if !File.exists?(root_path)
        raise Error.new "path does not exist: #{root_path}"
      elsif !File.directory?(root_path)
        raise Error.new "path is not a directory: #{root_path}"
      elsif !File::Info.readable?(root_path)
        raise Error.new "path is not readable: #{root_path}"
      end

      root_path_length = root_path.size

      result = [] of String

      stats = Stats.new

      pattern = Path[root_path].to_posix.join("**", "*").to_s
      match_opt = include_dotfiles ? File::MatchOptions::DotFiles : File::MatchOptions.glob_default
      files = Dir.glob(pattern, match: match_opt).reject { |path| File.directory?(path) }

      # Apply filtering if include or exclude patterns are provided
      if include_patterns || exclude_patterns
        # Convert absolute paths to relative paths for pattern matching
        relative_files = files.map { |path| Path[path[root_path_length..]].to_posix.to_s }
        filtered_relative = filter_files(relative_files, include_patterns, exclude_patterns)

        # Convert back to absolute paths
        filtered_set = filtered_relative.to_set
        files = files.select do |path|
          relative = Path[path[root_path_length..]].to_posix.to_s
          filtered_set.includes?(relative)
        end
      end

      files.each do |path|
        relative_path = Path[path[root_path_length..]].to_posix.to_s
        file_info = File.info(path)
        uncompressed_size = file_info.size

        io << "bake_file BakedFileSystem::BakedFile.new(\n"
        io << "  path:            " << relative_path.dump << ",\n"
        io << "  size:            " << uncompressed_size << ",\n"
        compressed = path.ends_with?("gz")
        stored_compressed = compress && !compressed

        io << "  compressed:      " << compressed << ",\n"
        io << "  stored_compressed: " << stored_compressed << ",\n"
        io << "  modification_time: Time.unix(" << file_info.modification_time.to_unix << "),\n"
        io << "  digest:          " << file_digest(path).dump << ",\n"

        File.open(path, "rb") do |file|
          io << "  slice:         \""
          stored_size = 0_i64

          StringEncoder.open(io) do |encoder|
            stored_byte_counter = ByteCounter.new(encoder)

            if stored_compressed
              Compress::Gzip::Writer.open(stored_byte_counter) do |writer|
                IO.copy file, writer
              end
            else
              IO.copy file, stored_byte_counter
            end

            stored_size = stored_byte_counter.count
          end

          io << "\".to_slice,\n"
          stats.add_file(relative_path, uncompressed_size, stored_size)
        end

        io << ")\n"
        io << "\n"
      end

      begin
        stats.report_to(STDERR, max_size)
      rescue ex : Stats::SizeExceededError
        exit(1)
      end
    end

    private def self.file_digest(path : String) : String
      Digest::SHA256.hexdigest do |digest|
        File.open(path, "rb") do |file|
          buffer = Bytes.new(8192)

          loop do
            bytes_read = file.read(buffer)
            break if bytes_read == 0

            digest.update(buffer[0, bytes_read])
          end
        end
      end
    end
  end
end
