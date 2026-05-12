require "./spec_helper"
require "../src/baked_file_system/http"
require "compress/gzip"
require "http/client/response"
require "http/server"

class HTTPStorage
  extend BakedFileSystem
  bake_folder "./storage"
end

class HTTPIndexStorage
  extend BakedFileSystem
  bake_file "index.html", "Home\n"
end

class HTTPCustomStorage
  extend BakedFileSystem
  bake_file BakedFileSystem::BakedFile.new("raw.txt", 10, false, "Raw body\n!".to_slice, false)
end

def call_static_handler(
  handler,
  method = "GET",
  resource = "/lorem.txt",
  headers = HTTP::Headers.new,
  decompress = true,
  ignore_body = false,
)
  io = IO::Memory.new
  request = HTTP::Request.new(method, resource, headers)
  response = HTTP::Server::Response.new(io, request.version)
  context = HTTP::Server::Context.new(request, response)

  handler.call(context)
  response.close

  io.rewind
  HTTP::Client::Response.from_io(io, ignore_body: ignore_body, decompress: decompress)
end

describe BakedFileSystem::HTTP::StaticFileHandler do
  it "serves an embedded file" do
    response = call_static_handler(BakedFileSystem::HTTP::StaticFileHandler.new(HTTPStorage))

    response.status_code.should eq(200)
    response.headers["Content-Type"].should eq("text/plain")
    response.headers["Content-Length"].should eq(HTTPStorage.get("lorem.txt").size.to_s)
    response.body.should eq(HTTPStorage.get("lorem.txt").gets_to_end)
  end

  it "serves HEAD without a body" do
    response = call_static_handler(
      BakedFileSystem::HTTP::StaticFileHandler.new(HTTPStorage),
      method: "HEAD",
      ignore_body: true
    )

    response.status_code.should eq(200)
    response.headers["Content-Length"].should eq(HTTPStorage.get("lorem.txt").size.to_s)
    response.body.should be_empty
  end

  it "serves raw gzip bytes when accepted" do
    file = HTTPStorage.get("lorem.txt")
    headers = HTTP::Headers{"Accept-Encoding" => "gzip"}

    response = call_static_handler(
      BakedFileSystem::HTTP::StaticFileHandler.new(HTTPStorage),
      headers: headers,
      decompress: false
    )

    response.status_code.should eq(200)
    response.headers["Content-Encoding"].should eq("gzip")
    response.headers["Content-Length"].should eq(file.compressed_size.to_s)
    response.body.to_slice.should eq(file.raw)
  end

  it "does not add gzip content encoding to baked gzip files" do
    headers = HTTP::Headers{"Accept-Encoding" => "gzip"}

    response = call_static_handler(
      BakedFileSystem::HTTP::StaticFileHandler.new(HTTPStorage),
      resource: "/string_encoding/interpolation.gz",
      headers: headers,
      decompress: false
    )

    response.status_code.should eq(200)
    response.headers["Content-Encoding"]?.should be_nil
    response.body.should eq("\#{foo} {% macro %}\n")
  end

  it "serves byte ranges over the selected identity representation" do
    response = call_static_handler(
      BakedFileSystem::HTTP::StaticFileHandler.new(HTTPStorage),
      headers: HTTP::Headers{"Range" => "bytes=0-4"}
    )

    response.status_code.should eq(206)
    response.headers["Content-Range"].should eq("bytes 0-4/#{HTTPStorage.get("lorem.txt").size}")
    response.body.should eq("Lorem")
  end

  it "serves byte ranges over the selected gzip representation" do
    file = HTTPStorage.get("lorem.txt")
    headers = HTTP::Headers{
      "Accept-Encoding" => "gzip",
      "Range"           => "bytes=0-9",
    }

    response = call_static_handler(
      BakedFileSystem::HTTP::StaticFileHandler.new(HTTPStorage),
      headers: headers,
      decompress: false
    )

    response.status_code.should eq(206)
    response.headers["Content-Encoding"].should eq("gzip")
    response.headers["Content-Range"].should eq("bytes 0-9/#{file.compressed_size}")
    response.body.to_slice.should eq(file.raw[0, 10])
  end

  it "returns 416 for unsatisfiable ranges" do
    response = call_static_handler(
      BakedFileSystem::HTTP::StaticFileHandler.new(HTTPStorage),
      headers: HTTP::Headers{"Range" => "bytes=99999-100000"},
      ignore_body: true
    )

    response.status_code.should eq(416)
    response.headers["Content-Range"].should eq("bytes */#{HTTPStorage.get("lorem.txt").size}")
  end

  it "ignores unknown range units and serves the full response" do
    response = call_static_handler(
      BakedFileSystem::HTTP::StaticFileHandler.new(HTTPStorage),
      headers: HTTP::Headers{"Range" => "items=0-4"}
    )

    response.status_code.should eq(200)
    response.body.should eq(HTTPStorage.get("lorem.txt").gets_to_end)
  end

  it "serves multipart byte ranges" do
    response = call_static_handler(
      BakedFileSystem::HTTP::StaticFileHandler.new(HTTPStorage),
      headers: HTTP::Headers{"Range" => "bytes=0-4,6-10"}
    )

    response.status_code.should eq(206)
    response.headers["Content-Type"].should start_with("multipart/byteranges")
    response.body.should contain("Content-Range: bytes 0-4/#{HTTPStorage.get("lorem.txt").size}")
    response.body.should contain("Content-Range: bytes 6-10/#{HTTPStorage.get("lorem.txt").size}")
  end

  it "serves custom uncompressed files after computing fallback etags" do
    response = call_static_handler(
      BakedFileSystem::HTTP::StaticFileHandler.new(HTTPCustomStorage),
      resource: "/raw.txt"
    )

    response.status_code.should eq(200)
    response.headers["ETag"].should_not be_empty
    response.body.should eq("Raw body\n!")
  end

  it "returns not modified for matching etags" do
    handler = BakedFileSystem::HTTP::StaticFileHandler.new(HTTPStorage)
    first_response = call_static_handler(handler)

    response = call_static_handler(
      handler,
      headers: HTTP::Headers{"If-None-Match" => first_response.headers["ETag"]},
      ignore_body: true
    )

    response.status_code.should eq(304)
    response.body.should be_empty
  end

  it "serves index files for directory requests" do
    response = call_static_handler(BakedFileSystem::HTTP::StaticFileHandler.new(HTTPIndexStorage), resource: "/")

    response.status_code.should eq(200)
    response.body.should eq("Home\n")
  end

  it "redirects directory requests without trailing slash" do
    response = call_static_handler(
      BakedFileSystem::HTTP::StaticFileHandler.new(HTTPStorage),
      resource: "/filters",
      ignore_body: true
    )

    response.status_code.should eq(302)
    response.headers["Location"].should eq("/filters/")
  end

  it "lists baked directories" do
    response = call_static_handler(
      BakedFileSystem::HTTP::StaticFileHandler.new(HTTPStorage, index_file: nil),
      resource: "/filters/"
    )

    response.status_code.should eq(200)
    response.headers["Content-Type"].should eq("text/html; charset=utf-8")
    response.body.should contain("docs/")
    response.body.should contain("src/")
  end

  it "falls through on missing files" do
    response = call_static_handler(
      BakedFileSystem::HTTP::StaticFileHandler.new(HTTPStorage),
      resource: "/missing.txt"
    )

    response.status_code.should eq(404)
  end

  it "only serves files under the configured prefix" do
    response = call_static_handler(
      BakedFileSystem::HTTP::StaticFileHandler.new(HTTPStorage, prefix: "/assets"),
      resource: "/assets/lorem.txt"
    )

    response.status_code.should eq(200)
    response.body.should eq(HTTPStorage.get("lorem.txt").gets_to_end)

    missing_response = call_static_handler(
      BakedFileSystem::HTTP::StaticFileHandler.new(HTTPStorage, prefix: "/assets"),
      resource: "/assets-other/lorem.txt"
    )

    missing_response.status_code.should eq(404)
  end

  it "returns method not allowed when fallthrough is disabled" do
    response = call_static_handler(
      BakedFileSystem::HTTP::StaticFileHandler.new(HTTPStorage, fallthrough: false),
      method: "POST",
      ignore_body: true
    )

    response.status_code.should eq(405)
    response.headers["Allow"].should eq("GET, HEAD")
  end
end
