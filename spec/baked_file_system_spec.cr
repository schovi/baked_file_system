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
    baked_file.mime_type.should eq("image/png")

    baked_file = Storage.get("/lorem.txt")
    baked_file.name.should eq("lorem.txt")
    baked_file.size.should eq(669)
    baked_file.compressed_size.should eq(400)
    baked_file.mime_type.should eq("text/plain")
  end

  it "throw error for missing file" do
    expect_raises(BakedFileSystem::NoSuchFileError) do
      Storage.get("missing.file")
    end
  end

  it "can read file contents" do
    files = %w(images/sidekiq.png /lorem.txt)
    files.each do |path|
      baked_file = Storage.get(path)
      data = baked_file.read
      data.should eq(File.read(File.expand_path(File.join(__DIR__, "storage", path))))
    end
  end

  it "get correct content of file" do
    path = "images/sidekiq.png"
    baked_file = Storage.get(path)
    original_path = File.expand_path(File.join(__DIR__, "storage", path))

    slice = baked_file.to_slice(false)
    slice.should eq(read_slice(original_path))
    slice.size.should eq(baked_file.size)

    slice = baked_file.to_slice
    slice.size.should eq(baked_file.compressed_size)
  end

  it "can write directly to an IO" do
    io = MemoryIO.new
    file = Storage.get("images/sidekiq.png")
    sz = file.compressed_size
    file.write_to_io(io).should be_nil
    io.size.should eq(sz)

    io = MemoryIO.new
    file = Storage.get("images/sidekiq.png")
    sz = file.size
    file.write_to_io(io, compressed: false).should be_nil
    io.size.should eq(sz)
  end
end

def read_slice(path)
  File.open(path, "rb") do |io|
    Slice(UInt8).new(io.size).tap do |buf|
      io.read_fully(buf)
    end
  end
end
