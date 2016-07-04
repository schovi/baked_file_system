require "base64"

module BakedFileSystem
  module Loader
    def self.load(root_path)
      root_path_length = root_path.size

      result = [] of String

      files = Dir.glob(File.join(root_path, "**", "*")).
                  # Reject hidden entities and directories
                  reject { |path| File.directory?(path) || !(path =~ /(\/\..+)/).nil? }

      files.each do |path|
        # encoded_path,encoded_mime_type,size,urlsafe_encoded_content
        entity = [] of String

        # File name
        entity << Base64.strict_encode(path[root_path_length..-1])
        # Mime type
        entity << Base64.strict_encode(`file -b --mime-type #{path}`.strip)
        # Size
        entity << File.stat(path).size.to_s
        # Content
        entity << Base64.urlsafe_encode(File.read(path))

        result << entity.join(",")
      end

      result.join("\n")
    end
  end
end
