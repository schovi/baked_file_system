require "./spec_helper"

class Storage
  BakedFs.load("./storage", __DIR__)
end

describe BakedFs do
  it "load only files without hidden one" do
    Storage.files.size.should eq(2)
  end

  it "get correct file name" do
    baked_file = Storage.get("images/pixel.png")

    baked_file.name.should eq("pixel.png")
  end

  it "throw error for missing file" do
    expect_raises(BakedFs::NoSuchFileError) do
      Storage.get("missing.file")
    end
  end

  it "get correct content of file" do
    path = "images/pixel.png"
    baked_file = Storage.get(path)
    original_path = Storage.original_path(path)

    baked_file.read.should eq(File.read(original_path))
  end
end
