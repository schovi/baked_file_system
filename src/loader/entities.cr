require "base64"
require "json"

module BakedFs
  module Loader
    def self.load(path)
      Folder.load(path)
    end

    abstract class Entity
    end

    class Folder < Entity
      getter name
      getter folders
      getter files

      @name    : String
      @folders : Array(Folder)
      @files   : Array(File)

      def self.load(path)
        glob    = ::File.join(path, "*")

        folders = Array(Folder).new
        files   = Array(File).new

        ::Dir.glob(glob).each do |entity_path|
          # Skip hidden files
          next if ::File.basename(entity_path).starts_with?(".")

          case
          when ::File.directory?(entity_path)
            folders.push(Folder.load(entity_path))
          when ::File.file?(entity_path)
            files.push(File.load(entity_path))
          else
            raise "Unknow entity type with path: #{entity_path}"
          end
        end

        Folder.new(
          name:    ::File.basename(path),
          folders: folders,
          files:   files
        )
      end

      def initialize(@name, @folders, @files)
      end

      # Serialize
      def to_json
        String.build do |io|
          to_json(io)
        end
      end

      def to_json(io)
        io.json_object do |object|
          object.field "name", name

          object.field "folders" do
            io.json_array do |array|
              folders.each do |folder|
                array << folder
              end
            end
          end

          object.field "files" do
            io.json_array do |array|
              files.each do |file|
                array << file
              end
            end
          end
        end
      end

      # def to_s
      #   name.colorize.mode(:bold)
      # end
      #
      # def inspect
      #   to_s
      # end
    end

    class File < Entity
      getter name
      getter content

      @name    : String
      @content : String

      def self.load(path)
        content = ::File.read(path)

        File.new(
          name:    ::File.basename(path),
          content: Base64.encode(content)
        )
      end

      def initialize(@name, @content)
      end

      # Serialize
      def to_json
        String.build do |io|
          to_json(io)
        end
      end

      def to_json(io)
        io.json_object do |object|
          object.field "name", name
          object.field "content", content
        end
      end
    end
  end
end
