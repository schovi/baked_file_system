require "./spec_helper"

class Storage
  extend BakedFileSystem
  bake_folder "./storage"
end

class ManualStorage
  extend BakedFileSystem
  bake_file "hello-world.txt", "Hello World\n"
end

class MutlipleStorage
  extend BakedFileSystem
  bake_folder "./storage"

  it "raises for empty folder" do
    expect_raises(Exception, "no files in") do
      bake_folder "./empty_storage"
    end
  end
end

class StorageWithHidden
  extend BakedFileSystem
  bake_folder "./storage", include_dotfiles: true
end

def read_slice(path)
  File.open(path, "rb") do |io|
    Slice(UInt8).new(io.size).tap do |buf|
      io.read_fully(buf)
    end
  end
end

describe BakedFileSystem do
  it "load only files without hidden one" do
    Storage.files.size.should eq(4)
    Storage.get?(".hidden/hidden_file.txt").should be_nil
  end

  it "can include hidden files if requested" do
    StorageWithHidden.get(".hidden/hidden_file.txt").gets_to_end.should eq "should not be included\n"
  end

  it "get correct file attributes" do
    baked_file = Storage.get("images/sidekiq.png")
    baked_file.size.should eq(52949)
    baked_file.compressed_size.should be_close 47883, 40

    baked_file = Storage.get("/lorem.txt")
    baked_file.size.should eq(669)
    baked_file.compressed_size.should be_close 400, 12
  end

  it "throw error for missing file" do
    expect_raises(BakedFileSystem::NoSuchFileError) do
      Storage.get("missing.file")
    end
    Storage.get?("missing.file").should be_nil
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
    io = IO::Memory.new
    file = Storage.get("images/sidekiq.png")
    sz = file.compressed_size
    file.write_to_io(io).should be_nil
    io.size.should eq(sz)

    io = IO::Memory.new
    file = Storage.get("images/sidekiq.png")
    sz = file.size
    file.write_to_io(io, compressed: false).should be_nil
    io.size.should eq(sz)
  end

  it "handles interpolation in content" do
    String.new(Storage.get("string_encoding/interpolation.gz").to_slice).should eq "\#{foo} \{% macro %}\n"
  end

  describe ManualStorage do
    it do
      file = ManualStorage.get("hello-world.txt")
      file.size.should eq 12
      file.gets_to_end.should eq "Hello World\n"
    end
  end
end
