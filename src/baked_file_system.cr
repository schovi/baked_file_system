require "base64"
require "gzip"
require "./baked_file_system/*"

module BakedFileSystem
  class NoSuchFileError < Exception
  end

  class BakedFile < IO
    getter path : String
    getter mime_type : String
    getter size : Int32
    getter slice : Bytes
    getter compressed_size : Int32

    # Whether this file compressed. If not, it is decompressed on read.
    getter? compressed : Bool

    def initialize(@path, @mime_type, @size, @compressed, @slice)
      @compressed_size = @slice.bytesize

      @memory_io = IO::Memory.new(@slice)
      @wrapped_io = compressed? ? @memory_io : Gzip::Reader.new(@memory_io)
    end

    def name
      File.basename(path)
    end

    def read(slice : Bytes)
      @wrapped_io.read(slice)
    end

    def write(slice : Bytes)
      raise "Can't write to BakedFileSystem::BakedFile"
    end

    def rewind
      @memory_io.rewind
      @wrapped_io = compressed? ? @memory_io : Gzip::Reader.new(@memory_io)
    end

    def to_slice
      @slice.dup
    end

    # Return the data for this file as a String.
    #
    # DEPRECATED: `BakedFile` can be used as an IO directly. Use `gets_to_end` instead
    def read
      gets_to_end
    end

    # Return the data for this file as a URL-safe Base64-encoded
    # String.
    #
    # DEPRECATED: `BakedFile` can be used as an IO directly.
    def to_encoded(compressed = true)
      if compressed
        raw = @slice
      else
        raw = read
        rewind
      end
      Base64.urlsafe_encode raw
    end

    # Write the file's data to the given IO, minimizing any
    # memory copies or unnecessary conversions.
    #
    # DEPRECATED: `BakedFile` can be used as an IO directly.
    def write_to_io(io, compressed = true)
      if compressed
        io.write(@slice)
      else
        IO.copy(self, io)
      end

      nil
    end

    # Return the file's data as a Slice(UInt8)
    #
    # DEPRECATED: `BakedFile` can be used as an IO directly.
    def to_slice(compressed)
      if compressed
        to_slice
      else
        Bytes.new(size).tap do |slice|
          read(slice)
        end
      end
    end
  end

  def get(path)
    path = path.strip
    path = "/" + path unless path.starts_with?("/")

    file = @@files.find do |file|
      file.path == path
    end

    raise NoSuchFileError.new("get: #{path}: No such file") unless file

    file.rewind
    file
  end

  def files
    @@files
  end

  # Creates a baked file system and loads contents of files in *path*.
  # If *path* is relative, it will be based on *dir* which defaults to `__DIR__`.
  # It will raise if there are no files found in *path* unless *allow_empty* is set to `true`.
  macro load(path, dir = __DIR__, allow_empty = false)
    {% raise "BakedFileSystem.load expects `path` to be a StringLiteral." unless path.is_a?(StringLiteral) %}
    extend BakedFileSystem

    @@files = [] of BakedFileSystem::BakedFile

    {{ run("./loader", path, dir) }}

    {% unless allow_empty %}
    raise "BakedFileSystem empty: no files in #{File.expand_path({{ path }}, {{ dir }})}" if @@files.size == 0
    {% end %}
  end
end
