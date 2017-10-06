require "base64"

module BakedFileSystem
  module Loader
    class Error < Exception
    end

    def self.load(io, root_path)
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

      files.each do |path|
        # encoded_path,encoded_mime_type,size,compressed_size,urlsafe_encoded_gzipped_content
        entity = [] of String

        content = if path.ends_with?("gz")
          `cat #{path} | #{b64cmd}`
        else
          `gzip -c -9 #{path} | #{b64cmd}`
        end
        rawcontent = Base64.decode(content)

        io << "@@files << BakedFileSystem::BakedFile.new(\n"
        io << "  path:            " << path[root_path_length..-1].dump << ",\n"
        io << "  mime_type:       " << (mime_type(path) || `file -b --mime-type #{path}`.strip).dump << ",\n"
        io << "  size:            " << File.stat(path).size << ",\n"
        io << "  compressed_size: " << rawcontent.size << ",\n"
        io << "  encoded:         " << Base64.urlsafe_encode(rawcontent).dump << ",\n"
        io << ")\n"
        io << "\n"
      end
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
