require "./spec_helper"
require "../src/loader/loader"

describe BakedFileSystem::Loader do
  it "raises if path does not exist" do
    expect_raises BakedFileSystem::Loader::Error, "path does not exist" do
      BakedFileSystem::Loader.load(IO::Memory.new, File.expand_path(File.join(__DIR__, "invalid_path")))
    end
  end
end
