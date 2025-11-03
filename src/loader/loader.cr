require "base64"
require "compress/gzip"
require "./string_encoder"
require "./stats"
require "./byte_counter"

module BakedFileSystem
  module Loader
    class Error < Exception
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
