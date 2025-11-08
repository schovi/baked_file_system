require "base64"
require "compress/gzip"
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

    def self.load(io, root_path, include_dotfiles = false, max_size : Int64? = nil)
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

      files.each do |path|
        relative_path = Path[path[root_path_length..]].to_posix.to_s
        uncompressed_size = File.info(path).size

        io << "bake_file BakedFileSystem::BakedFile.new(\n"
        io << "  path:            " << relative_path.dump << ",\n"
        io << "  size:            " << uncompressed_size << ",\n"
        compressed = path.ends_with?("gz")

        io << "  compressed:      " << compressed << ",\n"

        byte_counter = ByteCounter.new(io)

        File.open(path, "rb") do |file|
          io << "  slice:         \""

          StringEncoder.open(byte_counter) do |encoder|
            if compressed
              IO.copy file, encoder
            else
              Compress::Gzip::Writer.open(encoder) do |writer|
                IO.copy file, writer
              end
            end

            io << "\".to_slice,\n"
          end
        end

        compressed_size = byte_counter.count
        stats.add_file(relative_path, uncompressed_size, compressed_size)

        io << ")\n"
        io << "\n"
      end

      begin
        stats.report_to(STDERR, max_size)
      rescue ex : Stats::SizeExceededError
        exit(1)
      end
    end
  end
end
