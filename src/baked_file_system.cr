require "base64"
require "gzip"
require "./baked_file_system/*"

# A `BakedFileSystem` allows to include ("bake") static files into a compiled
# binary and make them accessible at runtime using their path.
#
# ## Usage
# ```crystal
# # Using BakedFileSystem.load
# class MyFileSystem
#   extend BakedFileSystem
#   bake_folder "path/to/root/folder"
# end
#
# # Creating a file manually
# class MyFileSystem
#   extend BakedFileSystem
#   bake_file "hello-world.txt", "Hello World\n"
# end
# ```
module BakedFileSystem
  # This error is raised when trying to access a non-existing file on a
  # `BakedFileSystem`.
  class NoSuchFileError < Exception
  end

  # `BakedFile` represents a virtual file in a `BakedFileSystem`.
  #
  # # Usage
  #
  # ```crystal
  # file = MyFileSystem.get("hello-world.txt")
  # file.path        # => "hello-world.txt"
  # file.size        # => 12
  # file.gets_to_end # => "Hello World\n"
  # file.compressed? # => false
  # ```
  class BakedFile < IO
    # Returns the path in the virtual file system.
    getter path : String

    getter mime_type : String

    # Returns the size of this virtual file.
    getter size : Int32

    # Returns whether this file is compressed. If not, it is decompressed on read.
    getter? compressed : Bool

    def initialize(@path, @mime_type, @size, @compressed, @slice : Bytes)
      @path = "/" + @path unless @path.starts_with? '/'
      @memory_io = IO::Memory.new(@slice)
      @wrapped_io = compressed? ? @memory_io : Gzip::Reader.new(@memory_io)
    end

    def read(slice : Bytes)
      @wrapped_io.read(slice)
    end

    # Returns the compressed size of this virtual file.
    #
    # See `#size` for the real size of the (uncompressed) file.
    def compressed_size
      @slice.bytesize
    end

    def write(slice : Bytes)
      raise "Can't write to BakedFileSystem::BakedFile"
    end

    def rewind
      @memory_io.rewind
      @wrapped_io = compressed? ? @memory_io : Gzip::Reader.new(@memory_io)
    end

    # Returns a `Bytes` holding the (compressed) content of this virtual file.
    # This data needs to be extracted using a `Gzip::Reader` unless `#compressed?` is true.
    def to_slice : Bytes
      @slice
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

  # Returns a `BakedFile` at *path*.
  #
  # Raises `NoSuchFileError` if the virtual file does not exist.
  def get(path : String) : BakedFile
    get?(path) || raise NoSuchFileError.new("get: #{path}: No such file")
  end

  # Returns a `BakedFile` at *path* or `nil` if the virtual file does not exist.
  def get?(path : String) : BakedFile?
    path = path.strip
    path = "/" + path unless path.starts_with?("/")

    file = @@files.find do |file|
      file.path == path
    end

    return nil unless file

    file.rewind
    file
  end

  # Returns all virtual files in this file system.
  def files : Array(BakedFileSystem::BakedFile)
    @@files
  end

  macro extended
    @@files = [] of BakedFileSystem::BakedFile

    macro bake_folder(path, dir = __DIR__, allow_empty = false)
      BakedFileSystem.bake_folder(\{{ path }}, \{{ dir }}, \{{ allow_empty }})
    end
  end

  # Creates a baked file system and loads contents of files in *path*.
  # If *path* is relative, it will be based on *dir* which defaults to `__DIR__`.
  # It will raise if there are no files found in *path* unless *allow_empty* is set to `true`.
  #
  # DEPRECATED: Use `extend BakedFileSystem` and `bake_folder` instead.
  macro load(path, dir = __DIR__, allow_empty = false)
    extend BakedFileSystem
    bake_folder {{ path }}, {{ dir }}, {{ allow_empty }}
  end

  # Bakes all files in *path* into this baked file system.
  # If *path* is relative, it will be based on *dir* which defaults to `__DIR__`.
  # It will raise if there are no files found in *path* unless *allow_empty* is set to `true`.
  macro bake_folder(path, dir = __DIR__, allow_empty = false)
    {% raise "BakedFileSystem.load expects `path` to be a StringLiteral." unless path.is_a?(StringLiteral) %}

    %files_size_ante = @@files.size

    {{ run("./loader", path, dir) }}

    {% unless allow_empty %}
    raise "BakedFileSystem empty: no files in #{File.expand_path({{ path }}, {{ dir }})}" if @@files.size - %files_size_ante == 0
    {% end %}
  end

  # Adds a baked *file* to this file system.
  def bake_file(file : BakedFile)
    @@files << file
  end

  # Creates a `BakedFile` at *path* with content *content* and adds it to this file system.
  def bake_file(path : String, content)
    bake_file BakedFileSystem::BakedFile.new(path, "no/mime", content.size, true, content.to_slice)
  end
end
