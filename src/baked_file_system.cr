require "base64"
require "zlib"
require "./baked_file_system/*"

module BakedFileSystem
  class NoSuchFileError < Exception
  end

  struct BakedFile
    getter! name : String
    getter! path : String
    getter! mime_type : String
    getter! size : Int32
    getter! encoded : String
    getter! compressed_size : Int32

    @slice : Slice(UInt8)?
    @io : IO?

    def initialize(@path, @mime_type, @size, @compressed_size, @encoded)
      @name = File.basename(path)
    end

    # Return the data for this file as a String.
    def read
      String.new(to_slice(false))
    end

    # Return the data for this file as a URL-safe Base64-encoded
    # String.
    def to_encoded(compressed = true)
      if compressed
        encoded
      else
        Base64.urlsafe_encode(to_slice(false))
      end
    end

    # Write the file's data to the given IO, minimizing any
    # memory copies or unnecessary conversions.
    def write_to_io(io, compressed = true)
      if compressed
        io.write(_to_slice)
      else
        _decompress_to_io(io)
      end
      
      nil
    end

    # Return the file's data as a Slice(UInt8)
    def to_slice(compressed = true)
      if compressed
        _to_slice
      else
        io = IO::Memory.new
        _decompress_to_io(io)
        io.to_slice
      end
    end

    private def _to_io
      @io ||= IO::Memory.new(_to_slice)
    end

    private def _to_slice
      @slice ||= Base64.decode(encoded)
    end

    private def _decompress_to_io(io)
      Zlib::Inflate.gzip(_to_io) do |gz|
        IO.copy(gz, io)
      end

      io
    end
  end

  def get(path)
    path = path.strip
    path = "/" + path unless path.starts_with?("/")

    file = @@files.find do |file|
      file.path == path
    end

    return file if file

    raise NoSuchFileError.new("get: #{path}: No such file")
  end

  def files
    @@files
  end

  macro load(path, source = "")
    extend BakedFileSystem

    @@files = [] of BakedFileSystem::BakedFile

    source = {{ run("./loader", path, source).stringify }}
    source.each_line do |line|
      parts = line.split("|")

      @@files << BakedFileSystem::BakedFile.new(
        path:            parts[0], 
        mime_type:       parts[1], 
        size:            parts[2].to_i32, 
        compressed_size: parts[3].to_i32, 
        encoded:         parts[4].strip
      )
    end
  end
end
