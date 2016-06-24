require "json"

module BakedFs
  module Core
    class NoSuchFileOrDirectoryError < Exception
    end

    struct Folder
      JSON.mapping({
        name:    String,
        folders: Array(Folder),
        files:   Array(File)
      })

      def get(path = nil)
        parts = path ? path.split(File::SEPARATOR) : Array(String).new

        parts.reduce(self) do |folder, part|
          if folder.is_a?(Folder)
            next_file = folder.files.find do |next_file|
              next_file.name == part
            end

            next next_file if next_file

            next_folder = folder.folders.find do |next_folder|
              next_folder.name == part
            end

            next next_folder if next_folder
          end

          raise NoSuchFileOrDirectoryError.new(path)
        end
      end
    end

    struct File
      JSON.mapping({
        name:    String,
        content: String
      })
    end

    def root : Folder
      @@root
    end

    def ls(path = nil)
      # TODO: should return list of items

      get(path)
    rescue NoSuchFileOrDirectoryError
      raise NoSuchFileOrDirectoryError.new("ls: #{path}: No such file or directory")
    end

    def get(path = nil)
      root.get(path)
    end

    macro load(path, source = nil)
      extend BakedFs::Core

      @@root = BakedFs::Core::Folder.from_json(
        {{ run("../loader", path.resolve, source || "").stringify }}
      )
    end
  end
end
