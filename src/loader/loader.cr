require "base64"

module BakedFileSystem
  module Loader
    def self.load(root_path)
      root_path_length = root_path.size

      result = [] of String

      files = Dir.glob(File.join(root_path, "**", "*"))
                 # Reject hidden entities and directories
                 .reject { |path| File.directory?(path) || !(path =~ /(\/\..+)/).nil? }

      files.each do |path|
        # encoded_path,encoded_mime_type,size,compressed_size,urlsafe_encoded_gzipped_content
        entity = [] of String

        # File name
        entity << path[root_path_length..-1]
        # Mime type
        entity << (mime_type(path) || `file -b --mime-type #{path}`.strip)
        # Size
        entity << File.stat(path).size.to_s
        # gzipped content
        content = if path.ends_with?("gz")
                    `cat #{path} | base64`
                  else
                    `gzip -c -9 #{path} | base64`
                  end
        rawcontent = Base64.decode(content)
        # compressed size
        entity << rawcontent.size.to_s
        entity << Base64.urlsafe_encode(rawcontent)

        result << entity.join("|")
      end

      result.join("\n")
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
