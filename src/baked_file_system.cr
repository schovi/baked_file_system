require "base64"
require "compress/gzip"
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

  # This error is raised when attempting to write to a read-only `BakedFile`.
  # Files embedded at compile-time cannot be modified at runtime.
  class ReadOnlyError < Exception
  end

  # This error is raised when attempting to bake a file with a path that already exists.
  # Duplicate file paths can occur when multiple `bake_folder` calls include files
  # with the same relative path.
  class DuplicatePathError < Exception
  end

  # `BakedFile` represents a virtual file in a `BakedFileSystem`.
  #
  # BakedFile is a read-only IO wrapper around files embedded at compile-time.
  # Write operations will raise `ReadOnlyError` since embedded files cannot be
  # modified at runtime.
  #
  # ## Architecture
  #
  # Files are stored compressed in the binary's read-only data section as byte slices.
  # On first access, BakedFile creates:
  #
  # 1. **Memory IO**: Wraps the compressed byte slice
  # 2. **Gzip Reader**: Wraps the memory IO for transparent decompression
  # 3. **Wrapped IO**: Either the memory IO (for .gz files) or gzip reader
  #
  # This lazy-loading approach minimizes memory usage:
  # - Compressed data stays in read-only binary section
  # - Decompression happens on-demand during read
  # - No heap allocation unless content is explicitly stored
  #
  # ## Streaming Behavior
  #
  # BakedFile is a forward-only stream by default:
  # - Read operations consume the stream
  # - Call `rewind` to return to the beginning
  # - Each `rewind` recreates the decompression reader (see `#rewind` for details)
  #
  # ## Thread Safety
  #
  # Each call to `get()` or `get?()` returns a new BakedFile instance with
  # independent state, making concurrent access safe.
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

    # Returns the size of this virtual file.
    getter size : Int32

    # Returns whether this file is compressed. If not, it is decompressed on read.
    getter? compressed : Bool

    @closed : Bool = false

    def initialize(@path, @size, @compressed, @slice : Bytes)
      @path = "/" + @path unless @path.starts_with? '/'
      @memory_io = IO::Memory.new(@slice)
      @wrapped_io = compressed? ? @memory_io : Compress::Gzip::Reader.new(@memory_io)
    end

    def read(slice : Bytes)
      check_open
      @wrapped_io.read(slice)
    end

    # Returns the compressed size of this virtual file.
    #
    # See `#size` for the real size of the (uncompressed) file.
    def compressed_size
      @slice.bytesize
    end

    def write(slice : Bytes) : Nil
      check_open
      raise ReadOnlyError.new("BakedFile is read-only. Files embedded at compile-time cannot be modified at runtime.")
    end

    # Rewinds the file to the beginning for re-reading.
    #
    # ## Implementation Note
    #
    # This method recreates the gzip decompression reader instead of rewinding it
    # because `Compress::Gzip::Reader` is a forward-only stream that doesn't support
    # seeking backward. This is intentional and necessary for correct behavior.
    #
    # ### Why Recreation is Required
    #
    # - `Compress::Gzip::Reader` maintains internal state during decompression
    # - This state cannot be reset to return to the beginning
    # - Creating a new reader over the rewound underlying stream is the only way to re-read
    #
    # ### Performance Implications
    #
    # - Creating a new reader is fast (no decompression happens yet)
    # - Decompression happens on-demand during read operations
    # - Memory usage is minimal (same underlying byte slice is reused)
    # - This is the standard approach for streaming decompression
    #
    # ### Alternatives Considered
    #
    # **Cache decompressed content:**
    # - Pro: True rewind without recreation
    # - Con: Significant memory overhead (defeats purpose of streaming)
    # - Con: Not suitable for large files
    # - Decision: Rejected
    #
    # **Add seeking to Gzip::Reader:**
    # - Pro: More intuitive API
    # - Con: Requires changes to Crystal standard library
    # - Con: Decompression algorithms are inherently forward-only
    # - Decision: Not feasible
    def rewind
      check_open
      @memory_io.rewind
      @wrapped_io = compressed? ? @memory_io : Compress::Gzip::Reader.new(@memory_io)
      nil
    end

    # Returns true if the file has been closed.
    def closed? : Bool
      @closed
    end

    # Closes the file and releases resources.
    # Can be called multiple times safely.
    # After closing, read operations will raise IO::Error.
    def close : Nil
      return if @closed

      @wrapped_io.close if @wrapped_io.responds_to?(:close)
      @memory_io.close if @memory_io.responds_to?(:close)
      @closed = true
    end

    # Ensures resources are freed when the object is garbage collected.
    def finalize
      close
    end

    private def check_open
      raise IO::Error.new("Closed stream") if @closed
    end

    # Returns a `Bytes` holding the (compressed) content of this virtual file.
    # This data needs to be extracted using a `Compress::Gzip::Reader` unless `#compressed?` is true.
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

  # Opens a file and yields it to the block, ensuring it's closed afterwards.
  #
  # ```
  # MyFiles.get("file.txt") do |file|
  #   file.gets_to_end
  # end
  # ```
  def get(path : String, &block : BakedFile -> T) : T forall T
    file = get(path)
    begin
      yield file
    ensure
      file.close
    end
  end

  # Returns a `BakedFile` at *path* or `nil` if the virtual file does not exist.
  def get?(path : String) : BakedFile?
    path = path.strip
    path = "/" + path unless path.starts_with?("/")

    template = @@files.find do |file|
      file.path == path
    end

    return nil unless template

    # Create a new instance to ensure thread safety and independent state
    BakedFile.new(template.path, template.size, template.compressed?, template.to_slice)
  end

  # Opens a file and yields it to the block, ensuring it's closed afterwards.
  # Returns nil if the file does not exist.
  #
  # ```
  # MyFiles.get?("file.txt") do |file|
  #   file.gets_to_end
  # end
  # ```
  def get?(path : String, &block : BakedFile -> T) : T? forall T
    file = get?(path)
    return nil unless file

    begin
      yield file
    ensure
      file.close
    end
  end

  # Returns all virtual files in this file system.
  def files : Array(BakedFileSystem::BakedFile)
    @@files
  end

  macro extended
    @@files = [] of BakedFileSystem::BakedFile
    @@paths = Set(String).new

    macro bake_folder(path, dir = __DIR__, allow_empty = false, include_dotfiles = false, include_patterns = nil, exclude_patterns = nil, max_size = nil)
      BakedFileSystem.bake_folder(\{{ path }}, \{{ dir }}, \{{ allow_empty }}, \{{ include_dotfiles }}, \{{ include_patterns }}, \{{ exclude_patterns }}, \{{ max_size }})
    end

    def self.add_baked_file(file : BakedFileSystem::BakedFile)
      if @@paths.includes?(file.path)
        raise BakedFileSystem::DuplicatePathError.new("Duplicate file path: #{file.path}. File already baked.")
      end
      @@paths << file.path
      @@files << file
    end

    def self.add_baked_file(file : BakedFileSystem::BakedFile)
      if @@paths.includes?(file.path)
        raise BakedFileSystem::DuplicatePathError.new("Duplicate file path: #{file.path}. File already baked.")
      end
      @@paths << file.path
      @@files << file
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
  # The *include_patterns* parameter accepts an array of glob patterns to include specific files.
  # The *exclude_patterns* parameter accepts an array of glob patterns to exclude specific files.
  # The *max_size* parameter can be used to enforce a maximum total compressed size limit (in bytes).
  macro bake_folder(path, dir = __DIR__, allow_empty = false, include_dotfiles = false, include_patterns = nil, exclude_patterns = nil, max_size = nil)
    {% raise "BakedFileSystem.load expects `path` to be a StringLiteral." unless path.is_a?(StringLiteral) %}

    %files_size_ante = @@files.size

    # Serialize filter patterns as JSON for passing to loader process
    {% if include_patterns || exclude_patterns %}
      # Build JSON string manually at compile time
      {% json_parts = [] of String %}
      {% if include_patterns %}
        {% include_json = "\"include\":[" + include_patterns.map { |p| "\"" + p + "\"" }.join(",") + "]" %}
        {% json_parts << include_json %}
      {% else %}
        {% json_parts << "\"include\":null" %}
      {% end %}
      {% if exclude_patterns %}
        {% exclude_json = "\"exclude\":[" + exclude_patterns.map { |p| "\"" + p + "\"" }.join(",") + "]" %}
        {% json_parts << exclude_json %}
      {% else %}
        {% json_parts << "\"exclude\":null" %}
      {% end %}
      {% filter_json = "{" + json_parts.join(",") + "}" %}
      {{ run("./loader", path, dir, include_dotfiles, filter_json, max_size || "nil") }}
    {% else %}
      {{ run("./loader", path, dir, include_dotfiles, "nil", max_size || "nil") }}
    {% end %}

    {% unless allow_empty %}
    raise "BakedFileSystem empty: no files in #{File.expand_path({{ path }}, {{ dir }})}" if @@files.size - %files_size_ante == 0
    {% end %}
  end

  # Adds a baked *file* to this file system.
  def bake_file(file : BakedFile)
    add_baked_file(file)
  end

  # Creates a `BakedFile` at *path* with content *content* and adds it to this file system.
  def bake_file(path : String, content)
    bake_file BakedFileSystem::BakedFile.new(path, content.size, true, content.to_slice)
  end
end
