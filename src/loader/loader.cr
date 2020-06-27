require "base64"
require "compress/gzip"
require "./string_encoder"

module BakedFileSystem
  module Loader
    class Error < Exception
    end

    def self.load(io, root_path)
      if !File.exists?(root_path)
        raise Error.new "path does not exist: #{root_path}"
      elsif !File.directory?(root_path)
        raise Error.new "path is not a directory: #{root_path}"
      elsif !File.readable?(root_path)
        raise Error.new "path is not readable: #{root_path}"
      end

      root_path_length = root_path.size

      result = [] of String

      files = Dir.glob(File.join(root_path, "**", "*"))
                 # Reject hidden entities and directories
                 .reject { |path| File.directory?(path) || !(path =~ /(\/\..+)/).nil? }

      files.each do |path|
        io << "bake_file BakedFileSystem::BakedFile.new(\n"
        io << "  path:            " << path[root_path_length..-1].dump << ",\n"
        io << "  size:            " << File.info(path).size << ",\n"
        compressed = path.ends_with?("gz")

        io << "  compressed:      " << compressed << ",\n"

        File.open(path, "rb") do |file|
          io << "  slice:         \""

          StringEncoder.open(io) do |encoder|
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

        io << ")\n"
        io << "\n"
      end
    end
  end
end
