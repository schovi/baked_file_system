require "base64"

module BakedFileSystem
  module Loader
    class Error < Exception
    end

    def self.load(root_path)
      if !File.exists?(root_path)
        raise Error.new "path does not exist: #{root_path}"
      elsif !File.directory?(root_path)
        raise Error.new "path is not a directory: #{root_path}"
      elsif !File.readable?(root_path)
        raise Error.new "path is not readable: #{root_path}"
      end

      root_path_length = root_path.size

      result = [] of String

      files = Dir.glob(File.join(root_path, "**", "*"))
                 # Reject hidden entities and directories
                 .reject { |path| File.directory?(path) || !(path =~ /(\/\..+)/).nil? }

      if files.empty?
        raise Error.new "no files found: #{root_path}"
      end

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
                    `cat #{path} | #{b64cmd}`
                  else
                    `gzip -c -9 #{path} | #{b64cmd}`
                  end
        rawcontent = Base64.decode(content)
        # compressed size
        entity << rawcontent.size.to_s
        entity << Base64.urlsafe_encode(rawcontent)

        result << entity.join("|")
      end

      result.join("\n")
    end

    def self.b64cmd
      {% if flag?(:darwin) %}
        "base64"
      {% else %}
        "base64 -w 0"
      {% end %}
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
