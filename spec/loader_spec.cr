require "./spec_helper"
require "../src/loader/loader"

describe BakedFileSystem::Loader do
  describe "error handling" do
    it "fails on invalid path" do
      expect_raises BakedFileSystem::Loader::Error, "path does not exist" do
        BakedFileSystem::Loader.load(IO::Memory.new, File.expand_path(File.join(__DIR__, "invalid_path")))
      end
    end

    it "fails on non-directory path" do
      expect_raises BakedFileSystem::Loader::Error do
        BakedFileSystem::Loader.load(IO::Memory.new, File.expand_path(File.join(__DIR__, "spec_helper.cr")))
      end
    end
  end

  describe "successful loading" do
    it "loads files from directory" do
      output = IO::Memory.new
      storage_path = File.expand_path(File.join(__DIR__, "storage"))
      BakedFileSystem::Loader.load(output, storage_path)

      result = output.to_s
      result.should_not be_empty
      result.should contain("BakedFile.new")
    end

    it "generates valid Crystal code" do
      output = IO::Memory.new
      storage_path = File.expand_path(File.join(__DIR__, "storage"))
      BakedFileSystem::Loader.load(output, storage_path)

      # Generated code should contain expected patterns
      code = output.to_s
      code.should contain("bake_file")
      code.should contain("BakedFile.new")
      code.should contain(".to_slice")
    end

    it "includes file metadata in generated code" do
      output = IO::Memory.new
      storage_path = File.expand_path(File.join(__DIR__, "storage"))
      BakedFileSystem::Loader.load(output, storage_path)

      code = output.to_s
      # Should contain path reference
      code.should contain("lorem")
      # Should contain numeric values (sizes)
      code.should match(/\d+/)
    end
  end

  describe "dotfile handling" do
    it "excludes dotfiles by default" do
      output = IO::Memory.new
      storage_path = File.expand_path(File.join(__DIR__, "storage"))
      BakedFileSystem::Loader.load(output, storage_path, include_dotfiles: false)

      code = output.to_s
      code.should_not contain("hidden_file")
    end

    it "includes dotfiles when requested" do
      output = IO::Memory.new
      storage_path = File.expand_path(File.join(__DIR__, "storage"))
      BakedFileSystem::Loader.load(output, storage_path, include_dotfiles: true)

      code = output.to_s
      code.should contain("hidden_file")
    end
  end

  describe "empty directory handling" do
    it "generates no file entries for empty directory" do
      Dir.mkdir_p("spec/loader_empty_test")

      begin
        output = IO::Memory.new
        empty_path = File.expand_path("spec/loader_empty_test")
        BakedFileSystem::Loader.load(output, empty_path)

        code = output.to_s
        # Empty directory should produce no BakedFile entries
        code.should_not contain("BakedFile.new")
      ensure
        Dir.delete("spec/loader_empty_test")
      end
    end
  end

  describe "path normalization" do
    it "converts paths to POSIX format" do
      output = IO::Memory.new
      storage_path = File.expand_path(File.join(__DIR__, "storage"))
      BakedFileSystem::Loader.load(output, storage_path)

      code = output.to_s
      # All paths should use forward slash
      code.should contain("/lorem.txt")
      code.should contain("/images/sidekiq.png")
    end
  end

  describe "file content encoding" do
    it "properly encodes text files" do
      output = IO::Memory.new
      storage_path = File.expand_path(File.join(__DIR__, "storage"))
      BakedFileSystem::Loader.load(output, storage_path)

      code = output.to_s
      # Should contain slice references
      code.should contain(".to_slice")
      code.should contain("path:")
      code.should contain("size:")
    end
  end
end
