require "base64"
require "./baked_file_system/*"

module BakedFileSystem
  class NoSuchFileError < Exception
  end

  class BakedFile
    getter! path : String
    getter! mime : String
    getter! size : Int32
    getter! encoded : String

    @content : String?

    def initialize(@path, @mime, @size, @encoded)
    end

    def name
      @name ||= File.basename(path)
    end

    def read
      @content ||= begin
        slice = Base64.decode(encoded)
        String.new(slice)
      end
    end
  end

  def get(path)
    path = path.strip
    path = "/" + path unless path.starts_with?("/")

    file = @@files.find do |file|
      file.path == path
    end

    return file if file

    raise NoSuchFileError.new("get: #{path}: No such file or directory")
  end

  def original_path(path)
    File.expand_path(File.join(@@original_source, @@original_path, path))
  end

  def files
    @@files
  end

  macro load(path, source = "")
    extend BakedFileSystem

    @@original_path   = {{path}}
    @@original_source = {{source}}

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
