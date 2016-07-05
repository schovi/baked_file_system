require "base64"
require "./baked_file_system/*"

module BakedFileSystem
  class NoSuchFileError < Exception
  end

  class BakedFile
    getter! path : String
    getter! mime_type : String
    getter! size : Int32
    getter! encoded : String

    @slice   : Slice(UInt8)?
    @string  : String?
    @name    : String?

    def initialize(@path, @mime_type, @size, @encoded)
    end

    def name
      @name ||= File.basename(path)
    end

    def read
      @string ||= _read
    end

    def to_slice
      @slice ||= _to_slice
    end

    private def _read
      String.new(_to_slice)
    end

    private def _to_slice
      Base64.decode(encoded)
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
      parts = line.split(",")

      @@files << BakedFileSystem::BakedFile.new(
        Base64.decode_string(parts[0]),
        Base64.decode_string(parts[1]),
        parts[2].to_i32,
        parts[3].strip
      )
    end
  end
end
