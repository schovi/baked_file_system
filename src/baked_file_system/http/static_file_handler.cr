require "base64"
require "digest/sha256"
require "html"
require "http/server/handler"
require "mime"
require "mime/multipart"
require "uri"

class BakedFileSystem::HTTP::StaticFileHandler
  include ::HTTP::Handler

  private record DirectoryEntry, name : String, directory : Bool

  private record Representation,
    file : BakedFileSystem::BakedFile,
    path : String,
    content_type : String,
    size : Int64,
    gzip_encoded : Bool do
    def bytes : Bytes
      gzip_encoded ? file.raw : file.to_slice(false)
    end

    def io : IO
      gzip_encoded ? file.raw_io : file
    end
  end

  @prefix : String

  def initialize(
    @filesystem : BakedFileSystem,
    prefix : String = "/",
    @fallthrough : Bool = true,
    @directory_listing : Bool = true,
    @index_file : String? = "index.html",
  )
    @prefix = normalize_prefix(prefix)
  end

  def call(context) : Nil
    return unless check_request_method(context)

    route_path = route_path(context.request.path)
    return call_next(context) unless route_path
    return bad_request(context) if route_path.includes?('\0')

    if file = @filesystem.get?(route_path)
      return serve_file(context, file, route_path)
    end

    return call_next(context) unless directory?(route_path)

    unless context.request.path.ends_with?("/")
      return redirect_to_directory(context)
    end

    if index_file = index_file_for(route_path)
      return serve_file(context, index_file, index_file.path)
    end

    if @directory_listing
      serve_directory_listing(context, route_path)
    else
      call_next(context)
    end
  end

  private def check_request_method(context : ::HTTP::Server::Context) : Bool
    return true if context.request.method.in?("GET", "HEAD")

    if @fallthrough
      call_next(context)
    else
      context.response.status = :method_not_allowed
      context.response.headers.add("Allow", "GET, HEAD")
    end

    false
  end

  private def bad_request(context : ::HTTP::Server::Context) : Nil
    context.response.respond_with_status(:bad_request)
  end

  private def normalize_prefix(prefix : String) : String
    normalized = URI.decode(prefix.strip)
    normalized = "/" + normalized unless normalized.starts_with?("/")
    normalized = normalized.rstrip('/')
    normalized.empty? ? "/" : normalized
  end

  private def route_path(request_path : String?) : String?
    path = request_path || "/"
    return unless prefix_matches?(path)

    path = URI.decode(path)
    stripped = @prefix == "/" ? path : path[@prefix.size..]? || "/"
    stripped = "/" if stripped.empty?
    stripped = "/" + stripped unless stripped.starts_with?("/")

    Path.posix(stripped).expand("/").to_s
  end

  private def prefix_matches?(request_path : String) : Bool
    return true if @prefix == "/"

    request_path == @prefix || request_path.starts_with?("#{@prefix}/")
  end

  private def serve_file(context : ::HTTP::Server::Context, file : BakedFileSystem::BakedFile, path : String) : Nil
    representation = select_representation(context, file, path)
    set_file_headers(context, representation)

    if fresh_cache_request?(context, representation)
      context.response.status = :not_modified
      return
    end

    if range_header = context.request.headers["Range"]?
      serve_range(context, representation, range_header)
    else
      serve_full(context, representation)
    end
  end

  private def select_representation(context : ::HTTP::Server::Context, file : BakedFileSystem::BakedFile, path : String) : Representation
    gzip_encoded = file.stored_compressed? && !file.compressed? && context.request.headers.includes_word?("Accept-Encoding", "gzip")
    size = gzip_encoded ? file.raw.bytesize.to_i64 : file.size.to_i64
    content_type = MIME.from_filename(path, "application/octet-stream")

    Representation.new(file, path, content_type, size, gzip_encoded)
  end

  private def set_file_headers(context : ::HTTP::Server::Context, representation : Representation) : Nil
    context.response.content_type = representation.content_type
    context.response.headers["Accept-Ranges"] = "bytes"
    context.response.headers["ETag"] = etag(representation)
    context.response.headers["Content-Encoding"] = "gzip" if representation.gzip_encoded
    context.response.headers.add("Vary", "Accept-Encoding") unless representation.file.compressed?

    if modification_time = representation.file.modification_time
      context.response.headers["Last-Modified"] = ::HTTP.format_time(modification_time)
    end
  end

  private def serve_full(context : ::HTTP::Server::Context, representation : Representation) : Nil
    context.response.status = :ok
    context.response.content_length = representation.size
    IO.copy(representation.io, context.response) unless head_request?(context)
  end

  private def serve_range(context : ::HTTP::Server::Context, representation : Representation, range_header : String) : Nil
    range_header = range_header.lchop?("bytes=")
    unless range_header
      return range_not_satisfiable(context, representation.size)
    end

    ranges = parse_ranges(range_header, representation.size)
    unless ranges
      return bad_request(context)
    end

    if representation.size.zero? && ranges.size == 1 && ranges[0].begin.zero?
      context.response.status = :ok
      return
    end

    if ranges.any? { |range| range.begin >= representation.size }
      return range_not_satisfiable(context, representation.size)
    end

    ranges.map! { |range| range.begin..Math.min(range.end, representation.size - 1) }
    context.response.status = :partial_content

    if ranges.size == 1
      serve_single_range(context, representation, ranges.first)
    else
      serve_multiple_ranges(context, representation, ranges)
    end
  end

  private def serve_single_range(context : ::HTTP::Server::Context, representation : Representation, range : Range(Int64, Int64)) : Nil
    context.response.headers["Content-Range"] = "bytes #{range.begin}-#{range.end}/#{representation.size}"
    context.response.content_length = range.size
    return if head_request?(context)

    bytes = representation.bytes
    context.response.write(bytes[range.begin, range.size])
  end

  private def serve_multiple_ranges(context : ::HTTP::Server::Context, representation : Representation, ranges : Array(Range(Int64, Int64))) : Nil
    content_type = context.response.headers["Content-Type"]?

    MIME::Multipart.build(context.response) do |builder|
      context.response.headers["Content-Type"] = builder.content_type("byteranges")
      next if head_request?(context)

      bytes = representation.bytes

      ranges.each do |range|
        headers = ::HTTP::Headers{
          "Content-Range"  => "bytes #{range.begin}-#{range.end}/#{representation.size}",
          "Content-Length" => range.size.to_s,
        }
        headers["Content-Type"] = content_type if content_type

        builder.body_part(headers, IO::Memory.new(bytes[range.begin, range.size]))
      end
    end
  end

  private def range_not_satisfiable(context : ::HTTP::Server::Context, size : Int64) : Nil
    context.response.headers["Content-Range"] = "bytes */#{size}"
    context.response.status = :range_not_satisfiable
    context.response.close
  end

  private def parse_ranges(header : String, file_size : Int64) : Array(Range(Int64, Int64))?
    ranges = [] of Range(Int64, Int64)
    header.split(",") do |range|
      start_string, dash, finish_string = range.lchop(' ').partition("-")
      return if dash.empty?

      start = start_string.to_i64?
      return if start.nil? && !start_string.empty?

      if finish_string.empty?
        return if start_string.empty?
        finish = file_size
      else
        finish = finish_string.to_i64? || return
      end

      if file_size.zero?
        if start
          return [1_i64..0_i64]
        elsif finish <= 0
          return
        else
          start = finish = 0_i64
        end
      elsif !start
        start = {file_size - finish, 0_i64}.max
        finish = file_size - 1
      end

      parsed_range = start..finish
      return unless 0 <= parsed_range.begin <= parsed_range.end

      ranges << parsed_range
    end

    ranges unless ranges.empty?
  end

  private def fresh_cache_request?(context : ::HTTP::Server::Context, representation : Representation) : Bool
    if if_none_match = context.request.if_none_match
      if_none_match.any? { |candidate| candidate == "*" || candidate == context.response.headers["ETag"] }
    elsif if_modified_since = context.request.headers["If-Modified-Since"]?
      return false unless modification_time = representation.file.modification_time

      header_time = ::HTTP.parse_time(if_modified_since)
      !!(header_time && modification_time <= header_time + 1.second)
    else
      false
    end
  end

  private def etag(representation : Representation) : String
    token = String.build do |io|
      io << representation.path
      io << '\0'
      io << digest(representation)
      io << '\0'
      io << representation.size
      io << '\0'
      io << representation.file.compressed_size
      io << '\0'
      io << representation.file.modification_time.try(&.to_unix)
      io << '\0'
      io << (representation.gzip_encoded ? "gzip" : "identity")
    end

    %(W/"#{Base64.urlsafe_encode(token)}")
  end

  private def digest(representation : Representation) : String
    return Digest::SHA256.hexdigest(representation.file.raw) if representation.gzip_encoded
    return Digest::SHA256.hexdigest(representation.file.raw) if representation.file.compressed?

    representation.file.digest || Digest::SHA256.hexdigest(representation.bytes)
  end

  private def head_request?(context : ::HTTP::Server::Context) : Bool
    context.request.method == "HEAD"
  end

  private def directory?(path : String) : Bool
    directory_prefix = path.ends_with?("/") ? path : "#{path}/"
    @filesystem.files.any? { |file| file.path.starts_with?(directory_prefix) }
  end

  private def index_file_for(path : String) : BakedFileSystem::BakedFile?
    index_file = @index_file
    return unless index_file

    directory_path = path.ends_with?("/") ? path : "#{path}/"
    @filesystem.get?("#{directory_path}#{index_file}")
  end

  private def redirect_to_directory(context : ::HTTP::Server::Context) : Nil
    uri = context.request.uri.dup
    uri.path = "#{context.request.path}/"
    context.response.redirect(uri)
  end

  private def serve_directory_listing(context : ::HTTP::Server::Context, path : String) : Nil
    context.response.content_type = "text/html; charset=utf-8"
    return if head_request?(context)

    title = "Index of #{path}"
    context.response << "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>"
    context.response << HTML.escape(title)
    context.response << "</title></head><body><h1>"
    context.response << HTML.escape(title)
    context.response << "</h1><ul>"

    directory_entries(path).each do |entry|
      entry_name = entry.directory ? "#{entry.name}/" : entry.name
      context.response << "<li><a href=\""
      context.response << URI.encode_path(entry_name)
      context.response << "\">"
      context.response << HTML.escape(entry_name)
      context.response << "</a></li>"
    end

    context.response << "</ul></body></html>"
  end

  private def directory_entries(path : String) : Array(DirectoryEntry)
    prefix = path == "/" ? "/" : (path.ends_with?("/") ? path : "#{path}/")
    entries = {} of String => Bool

    @filesystem.files.each do |file|
      next unless file.path.starts_with?(prefix)

      remainder = file.path[prefix.size..]?
      next if remainder.nil? || remainder.empty?

      name, separator, _rest = remainder.partition("/")
      entries[name] = entries.fetch(name, false) || !separator.empty?
    end

    entries.map { |name, directory| DirectoryEntry.new(name, directory) }
      .sort_by { |entry| {entry.directory ? 0 : 1, entry.name.downcase} }
  end
end
