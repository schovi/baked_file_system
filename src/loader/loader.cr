require "base64"
require "gzip"

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
        io << "@@files << BakedFileSystem::BakedFile.new(\n"
        io << "  path:            " << path[root_path_length..-1].dump << ",\n"
        io << "  mime_type:       " << (mime_type(path) || `file -b --mime-type #{path}`.strip).dump << ",\n"
        io << "  size:            " << File.stat(path).size << ",\n"
        compressed = path.ends_with?("gz")

        io << "  compressed:      " << compressed << ",\n"

        File.open(path, "rb") do |file|
          io << "  slice:         \""

          Encoder.open(io) do |encoder|
            if compressed
              IO.copy file, encoder
            else
              Gzip::Writer.open(encoder) do |writer|
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

    class Encoder < IO
      def initialize(@io : IO)
      end

      def self.open(io : IO)
        encoder = new(io)
        yield encoder ensure encoder.close
      end

      def read(slice : Bytes)
        raise "Can't read from Encoder"
      end

      def write(slice : Bytes)
        slice.each do |byte|
          case byte
          when 35_u8..91_u8, 93_u8..127_u8
            @io << byte.chr
          else
            @io << "\\x"
            @io << '0' if byte < 16_u8
            @io << byte.to_s(16)
          end
        end
      end
    end

    # On OSX, the ancient `file` doesn't handle types like CSS and JS well at all.
    def self.mime_type(path)
      case File.extname(path)
      when ".txt"          then "text/plain"
      when ".htm", ".html" then "text/html"
      when ".css"          then "text/css"
      when ".js"           then "application/javascript"
      else                      nil
      end
    end
  end
end
