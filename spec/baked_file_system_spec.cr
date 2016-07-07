require "./spec_helper"

class Storage
  BakedFileSystem.load("./storage", __DIR__)
end

describe BakedFileSystem do
  it "load only files without hidden one" do
    Storage.files.size.should eq(2)
  end

  it "get correct file attributes" do
    baked_file = Storage.get("images/sidekiq.png")
    baked_file.name.should eq("sidekiq.png")
    baked_file.size.should eq(52949)
    baked_file.compressed_size.should eq(47862)

    baked_file = Storage.get("/lorem.txt")
    baked_file.name.should eq("lorem.txt")
    baked_file.size.should eq(669)
    baked_file.compressed_size.should eq(400)
  end

  it "get correct file mime type" do
    baked_file = Storage.get("images/sidekiq.png")
    baked_file.mime_type.should eq("image/png")
  end

  it "throw error for missing file" do
    expect_raises(BakedFileSystem::NoSuchFileError) do
      Storage.get("missing.file")
    end
  end

  it "get correct content of file" do
    path = "images/sidekiq.png"
    baked_file = Storage.get(path)
    original_path = File.expand_path(File.join(__DIR__, "storage", path))

    slice = baked_file.uncompressed_slice
    slice.should eq(read_slice(original_path))
    slice.size.should eq(baked_file.size)

    slice = baked_file.compressed_slice
    slice.size.should eq(baked_file.compressed_size)
  end
end

def read_slice(path)
  File.open(path, "rb") do |io|
    Slice(UInt8).new(io.size).tap do |buf|
      io.read_fully(buf)
    end
  end
end
