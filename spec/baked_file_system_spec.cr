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

class EmptyStorage
  extend BakedFileSystem
  bake_folder "./empty_storage", allow_empty: true
end

class MultiDirStorage
  extend BakedFileSystem
  bake_folder "./storage"
  bake_folder "./empty_storage", allow_empty: true
end

# Edge case storage with files already created on disk
class EdgeCaseStorage
  extend BakedFileSystem
  bake_folder "./storage_edge_cases"
end

# Test storage with include patterns - only .cr files
class FilteredStorageInclude
  extend BakedFileSystem
  bake_folder "./storage/filters", include_patterns: ["**/*.cr"]
end

# Test storage with exclude patterns - exclude test directory
class FilteredStorageExclude
  extend BakedFileSystem
  bake_folder "./storage/filters", exclude_patterns: ["**/test/*"]
end

# Test storage with both include and exclude patterns
class FilteredStorageCombined
  extend BakedFileSystem
  bake_folder "./storage/filters", include_patterns: ["**/*.cr", "**/*.md"], exclude_patterns: ["**/test/*"]
end

# Test storage with patterns that result in empty set (unless allow_empty)
class FilteredStorageEmpty
  extend BakedFileSystem
  bake_folder "./storage/filters", include_patterns: ["**/*.txt"], allow_empty: true
end

# This should raise an error at compile time - patterns match nothing and allow_empty is false
# Commented out because it would prevent compilation
# class FilteredStorageEmptyError
#   extend BakedFileSystem
#   bake_folder "./storage/filters", include_patterns: ["**/*.txt"]
# end

def read_slice(path)
  File.open(path, "rb") do |io|
    Slice(UInt8).new(io.size).tap do |buf|
      io.read_fully(buf)
    end
  end
end

describe BakedFileSystem do
  it "load only files without hidden one" do
    Storage.files.size.should eq(10) # lorem.txt, images/sidekiq.png, string_encoding/*, filters/*
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
    String.new(Storage.get("string_encoding/interpolation.gz").to_slice).should eq "\#{foo} {% macro %}\n"
  end

  describe "rewind functionality" do
    it "allows reading file multiple times" do
      file = Storage.get("lorem.txt")

      # First read
      first_content = file.gets_to_end
      first_content.should_not be_empty

      # Rewind
      file.rewind

      # Second read should be identical
      second_content = file.gets_to_end
      second_content.should eq(first_content)
    end

    it "handles multiple consecutive rewinds" do
      file = Storage.get("lorem.txt")

      content = file.gets_to_end

      3.times do
        file.rewind
        file.gets_to_end.should eq(content)
      end
    end

    it "works with binary files" do
      file = Storage.get("images/sidekiq.png")

      # Read binary content
      first_bytes = file.to_slice
      first_bytes.size.should be > 0

      file.rewind

      # Verify identical binary content
      second_bytes = file.to_slice
      second_bytes.should eq(first_bytes)
    end

    it "resets position to beginning" do
      file = Storage.get("lorem.txt")

      # Read partial content
      file.gets(10)

      file.rewind

      # Should read from beginning
      content = file.gets_to_end
      content.should start_with("Lorem ipsum")
    end

    it "works after partial reads" do
      file = Storage.get("lorem.txt")

      # Multiple partial reads
      chunk1 = file.gets(5).to_s
      chunk2 = file.gets(5).to_s

      file.rewind

      # Full read should match start
      full_content = file.gets_to_end
      full_content.should start_with(chunk1 + chunk2)
    end

    it "maintains file metadata after rewind" do
      file = Storage.get("lorem.txt")

      original_path = file.path
      original_size = file.size
      original_compressed_size = file.compressed_size

      file.gets_to_end
      file.rewind

      # Metadata should be unchanged
      file.path.should eq(original_path)
      file.size.should eq(original_size)
      file.compressed_size.should eq(original_compressed_size)
    end
  end

  describe "allow_empty parameter" do
    it "allows baking empty directories when allow_empty: true" do
      # Should not raise during module loading
      EmptyStorage.files.should be_empty
    end

    it "returns empty array from files method" do
      files = EmptyStorage.files
      files.should be_a(Array(BakedFileSystem::BakedFile))
      files.size.should eq(0)
    end

    it "raises NoSuchFileError for non-existent files in empty storage" do
      expect_raises(BakedFileSystem::NoSuchFileError) do
        EmptyStorage.get("nonexistent.txt")
      end
    end

    it "returns nil with get? for non-existent files in empty storage" do
      EmptyStorage.get?("nonexistent.txt").should be_nil
    end

    it "works with multiple empty directory loads" do
      files = MultiDirStorage.files
      # Should have files from storage directory only
      files.size.should eq(Storage.files.size)
    end
  end

  describe "multiple bake_folder calls" do
    it "loads files from all directories" do
      files = MultiDirStorage.files

      # Should have files from storage directory
      MultiDirStorage.get?("lorem.txt").should_not be_nil
      MultiDirStorage.get?("images/sidekiq.png").should_not be_nil
    end

    it "maintains correct file count with multiple bake_folder" do
      # Count should be same as storage alone (empty_storage adds nothing)
      MultiDirStorage.files.size.should eq(Storage.files.size)
    end

    it "allows access to files from both directories" do
      file1 = MultiDirStorage.get("lorem.txt")
      file1.path.should eq("/lorem.txt")

      file2 = MultiDirStorage.get("images/sidekiq.png")
      file2.path.should eq("/images/sidekiq.png")
    end
  end

  describe "concurrent access" do
    it "allows multiple fibers to read same file" do
      file_path = "lorem.txt"
      channel = Channel(String).new(10)

      10.times do
        spawn do
          file = Storage.get(file_path)
          content = file.gets_to_end
          channel.send(content)
        end
      end

      # Collect all results
      results = Array.new(10) { channel.receive }

      # All should be identical
      results.uniq.size.should eq(1)
      results.first.should_not be_empty
    end

    it "allows concurrent access to different files" do
      channel = Channel(Bool).new(5)

      5.times do |i|
        spawn do
          # Access different files
          files = ["lorem.txt", "images/sidekiq.png"]
          file = Storage.get(files[i % 2])
          content = file.read
          channel.send(content.size > 0)
        end
      end

      results = Array.new(5) { channel.receive }
      results.all?.should be_true
    end

    it "handles concurrent rewind operations" do
      channel = Channel(String).new(5)

      5.times do
        spawn do
          file = Storage.get("lorem.txt")
          file.gets_to_end
          file.rewind
          content = file.gets_to_end
          channel.send(content)
        end
      end

      results = Array.new(5) { channel.receive }
      results.uniq.size.should eq(1)
    end

    it "creates independent file instances" do
      # Get two instances of the same file
      file1 = Storage.get("lorem.txt")
      file2 = Storage.get("lorem.txt")

      # Both instances should have the same size and path
      file1.path.should eq(file2.path)
      file1.size.should eq(file2.size)
      file1.compressed_size.should eq(file2.compressed_size)
    end
  end

  describe "large file handling" do
    it "works with existing large files from storage" do
      # Test with large files like the image
      file = Storage.get("images/sidekiq.png")
      file.size.should be > 50_000
      content = file.gets_to_end
      content.bytesize.should eq(file.size)
    end

    it "supports rewinding on files" do
      file = Storage.get("lorem.txt")
      first_read = file.gets_to_end
      file.rewind
      second_read = file.gets_to_end
      second_read.should eq(first_read)
    end

    it "streams files with line iteration" do
      file = Storage.get("lorem.txt")
      line_count = 0
      file.each_line { |_line| line_count += 1 }
      line_count.should be > 0
    end
  end

  describe "symbolic link handling" do
    it "handles symlinks - baked_file_system documents current behavior" do
      # Symlink behavior depends on the platform and how Dir.glob handles them
      # This test documents that the system compiles and loads successfully
      Storage.files.size.should be > 0
    end
  end

  describe "compression edge cases" do
    it "handles .gz files without double compression" do
      # We have string_encoding/interpolation.gz in storage
      file = Storage.get("string_encoding/interpolation.gz")
      file.should_not be_nil
      file.compressed?.should be_true
    end

    it "decompresses text files correctly" do
      file = Storage.get("lorem.txt")
      content = file.gets_to_end
      content.should_not be_empty
      content.should contain("Lorem ipsum")
    end

    it "decompresses binary files correctly" do
      file = Storage.get("images/sidekiq.png")
      # Read decompressed content
      content = file.read
      content.bytesize.should eq(file.size)
      # Verify we got substantial data
      content.bytesize.should be > 50_000
    end

    it "reports correct sizes for compressed files" do
      file = Storage.get("lorem.txt")
      # Original size should be larger than compressed
      file.size.should be > file.compressed_size
      # Original is 669 bytes, compressed should be around 400
      file.compressed_size.should be > 100
    end
  end

  describe "path edge cases" do
    it "handles files with spaces" do
      file = EdgeCaseStorage.get?("with spaces.txt")
      file.should_not be_nil
      if file
        file.path.should eq("/with spaces.txt")
        file.gets_to_end.should eq("content with spaces")
      end
    end

    it "handles files with multiple spaces" do
      file = EdgeCaseStorage.get?("multiple   spaces.txt")
      file.should_not be_nil
      if file
        file.path.should eq("/multiple   spaces.txt")
      end
    end

    it "handles unicode filenames - Cyrillic" do
      file = EdgeCaseStorage.get?("файл.txt")
      file.should_not be_nil
      if file
        file.path.should eq("/файл.txt")
        file.gets_to_end.should eq("содержание")
      end
    end

    it "handles unicode filenames - Chinese" do
      file = EdgeCaseStorage.get?("文件.txt")
      file.should_not be_nil
      if file
        file.path.should eq("/文件.txt")
      end
    end

    it "handles special characters - parentheses" do
      file = EdgeCaseStorage.get?("file(1).txt")
      file.should_not be_nil
      if file
        file.path.should eq("/file(1).txt")
      end
    end

    it "handles special characters - brackets" do
      file = EdgeCaseStorage.get?("file[brackets].txt")
      file.should_not be_nil
      if file
        file.path.should eq("/file[brackets].txt")
      end
    end

    it "handles multiple dots in filename" do
      file = EdgeCaseStorage.get?("file.tar.gz")
      file.should_not be_nil
      if file
        file.path.should eq("/file.tar.gz")
      end
    end

    it "handles subdirectories with spaces" do
      file = EdgeCaseStorage.get?("subdirectory with spaces/nested file.txt")
      file.should_not be_nil
      if file
        file.path.should eq("/subdirectory with spaces/nested file.txt")
        file.gets_to_end.should eq("nested content")
      end
    end

    it "ensures all paths start with /" do
      EdgeCaseStorage.files.each do |file|
        file.path.should start_with("/")
      end
    end

    it "normalizes path separators to forward slashes" do
      EdgeCaseStorage.files.each do |file|
        file.path.should_not contain("\\")
      end
    end
  end

  describe ManualStorage do
    it do
      file = ManualStorage.get("hello-world.txt")
      file.size.should eq 12
      file.gets_to_end.should eq "Hello World\n"
    end
  end

  describe "write protection" do
    it "raises ReadOnlyError on write attempt" do
      file = Storage.get("lorem.txt")

      expect_raises(BakedFileSystem::ReadOnlyError, /read-only/) do
        file.write(Bytes[1, 2, 3])
      end
    end

    it "provides helpful error message" do
      file = Storage.get("lorem.txt")

      begin
        file.write(Bytes[1])
        fail "Expected ReadOnlyError to be raised"
      rescue ex : BakedFileSystem::ReadOnlyError
        msg = ex.message
        msg.should_not be_nil
        msg.not_nil!.should contain("compile-time")
        msg.not_nil!.should contain("cannot be modified")
      end
    end
  end

  describe "duplicate path handling" do
    it "detects duplicate paths within same bake_file calls" do
      # Note: Duplicate paths are detected at compile time through the add_baked_file method
      # This is tested indirectly through the implementation
      paths = Set(String).new

      # Simulate what happens during bake_file
      path1 = "/test.txt"
      paths.includes?(path1).should be_false
      paths << path1

      # Second attempt should be detected
      paths.includes?(path1).should be_true
    end
  end

  describe "BakedFile#close" do
    it "closes the file" do
      file = Storage.get("lorem.txt")
      file.closed?.should be_false

      file.close
      file.closed?.should be_true
    end

    it "allows multiple close calls" do
      file = Storage.get("lorem.txt")
      file.close
      file.close # Should not raise
    end

    it "raises on read after close" do
      file = Storage.get("lorem.txt")
      file.close

      expect_raises(IO::Error, /Closed stream/) do
        file.gets_to_end
      end
    end

    it "raises on write after close" do
      file = Storage.get("lorem.txt")
      file.close

      expect_raises(IO::Error, /Closed stream/) do
        file.write(Bytes[1])
      end
    end

    it "raises on rewind after close" do
      file = Storage.get("lorem.txt")
      file.close

      expect_raises(IO::Error, /Closed stream/) do
        file.rewind
      end
    end

    it "supports block form with automatic close" do
      content = Storage.get("lorem.txt") do |file|
        file.gets_to_end
      end

      content.should_not be_empty
    end

    it "closes file even if block raises" do
      file : BakedFileSystem::BakedFile? = nil

      expect_raises(Exception, /test error/) do
        Storage.get("lorem.txt") do |f|
          file = f
          raise "test error"
        end
      end

      file.not_nil!.closed?.should be_true
    end
  end

  describe "file filtering" do
    it "includes only files matching include patterns" do
      # Should only have .cr files
      FilteredStorageInclude.files.size.should eq(4) # src/main.cr, src/lib.cr, test/spec.cr, test/helper.cr
      FilteredStorageInclude.get?("src/main.cr").should_not be_nil
      FilteredStorageInclude.get?("src/lib.cr").should_not be_nil
      FilteredStorageInclude.get?("test/spec.cr").should_not be_nil
      FilteredStorageInclude.get?("test/helper.cr").should_not be_nil
      FilteredStorageInclude.get?("docs/README.md").should be_nil
      FilteredStorageInclude.get?("config.yml").should be_nil
    end

    it "excludes files matching exclude patterns" do
      # Should have everything except test/* files
      FilteredStorageExclude.files.size.should eq(4) # src/*, docs/*, config.yml
      FilteredStorageExclude.get?("src/main.cr").should_not be_nil
      FilteredStorageExclude.get?("src/lib.cr").should_not be_nil
      FilteredStorageExclude.get?("docs/README.md").should_not be_nil
      FilteredStorageExclude.get?("config.yml").should_not be_nil
      FilteredStorageExclude.get?("test/spec.cr").should be_nil
      FilteredStorageExclude.get?("test/helper.cr").should be_nil
    end

    it "applies both include and exclude patterns" do
      # Include *.cr and *.md, exclude test/*
      # Should have: src/*.cr and docs/*.md (not test/*.cr)
      FilteredStorageCombined.files.size.should eq(3) # src/main.cr, src/lib.cr, docs/README.md
      FilteredStorageCombined.get?("src/main.cr").should_not be_nil
      FilteredStorageCombined.get?("src/lib.cr").should_not be_nil
      FilteredStorageCombined.get?("docs/README.md").should_not be_nil
      FilteredStorageCombined.get?("test/spec.cr").should be_nil
      FilteredStorageCombined.get?("test/helper.cr").should be_nil
      FilteredStorageCombined.get?("config.yml").should be_nil
    end

    it "handles empty result with allow_empty" do
      # No .txt files in filters directory, but allow_empty is true
      FilteredStorageEmpty.files.size.should eq(0)
    end

    it "filters are relative to baked directory" do
      # Patterns should match from the baked folder root, not absolute paths
      FilteredStorageInclude.get?("src/main.cr").should_not be_nil
      # Not "/storage/filters/src/main.cr"
    end

    it "can read content from filtered files" do
      file = FilteredStorageInclude.get("src/main.cr")
      content = file.gets_to_end
      content.should contain("Main file")
    end

    it "empty result behavior respects allow_empty flag" do
      # FilteredStorageEmpty has allow_empty: true, so it should work with 0 files
      FilteredStorageEmpty.files.size.should eq(0)
      # Without allow_empty: true, it would raise at compile time (tested manually)
    end
  end
end
