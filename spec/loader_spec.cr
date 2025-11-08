require "./spec_helper"
require "../src/loader/loader"
require "../src/loader/stats"
require "../src/loader/byte_counter"

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

  describe "size tracking and reporting" do
    it "accepts max_size parameter" do
      stdout = IO::Memory.new

      # Should complete successfully with a large max_size
      BakedFileSystem::Loader.load(stdout, File.expand_path(File.join(__DIR__, "storage")), false, nil, nil, 10_000_000_i64)

      # Should generate code for the files
      stdout.to_s.should contain("BakedFile.new")
    end
  end
end

describe BakedFileSystem::Loader::Stats do
  describe "#add_file" do
    it "tracks file count and sizes" do
      stats = BakedFileSystem::Loader::Stats.new

      stats.add_file("/file1.txt", 1024_i64, 512_i64)
      stats.add_file("/file2.txt", 2048_i64, 1024_i64)

      stats.file_count.should eq(2)
      stats.total_uncompressed.should eq(3072_i64)
      stats.total_compressed.should eq(1536_i64)
    end

    it "tracks large files separately" do
      stats = BakedFileSystem::Loader::Stats.new

      # Small file - should not be tracked as large
      stats.add_file("/small.txt", 1024_i64, 512_i64)
      stats.large_files.size.should eq(0)

      # Large file (>1MB compressed) - should be tracked
      stats.add_file("/large.bin", 5_000_000_i64, 2_000_000_i64)
      stats.large_files.size.should eq(1)
      stats.large_files[0][0].should eq("/large.bin")
    end
  end

  describe "#compression_ratio" do
    it "calculates compression ratio correctly" do
      stats = BakedFileSystem::Loader::Stats.new

      stats.add_file("/file.txt", 1000_i64, 500_i64)
      stats.compression_ratio.should eq(50.0)

      stats.add_file("/file2.txt", 1000_i64, 250_i64)
      stats.compression_ratio.should eq(37.5)
    end

    it "returns 0 for empty stats" do
      stats = BakedFileSystem::Loader::Stats.new
      stats.compression_ratio.should eq(0.0)
    end
  end

  describe "#report_to" do
    it "outputs formatted report with file statistics" do
      stats = BakedFileSystem::Loader::Stats.new
      stats.add_file("/file1.txt", 1024_i64, 512_i64)
      stats.add_file("/file2.txt", 2048_i64, 1024_i64)

      io = IO::Memory.new
      stats.report_to(io)
      output = io.to_s

      output.should contain("BakedFileSystem: Embedded 2 files")
      output.should contain("KB")
      output.should contain("%")
    end

    it "warns about large files" do
      stats = BakedFileSystem::Loader::Stats.new
      stats.add_file("/huge.bin", 5_000_000_i64, 2_000_000_i64)

      io = IO::Memory.new
      stats.report_to(io)
      output = io.to_s

      output.should contain("WARNING")
      output.should contain("Large file detected")
      output.should contain("/huge.bin")
    end

    it "warns when total size exceeds threshold" do
      stats = BakedFileSystem::Loader::Stats.new
      # Add enough data to exceed default warning threshold (10MB)
      stats.add_file("/big1.bin", 20_000_000_i64, 11_000_000_i64)

      io = IO::Memory.new
      stats.report_to(io)
      output = io.to_s

      output.should contain("WARNING")
      output.should contain("significant")
    end

    it "raises error when max_size is exceeded" do
      stats = BakedFileSystem::Loader::Stats.new
      stats.add_file("/file.txt", 1000_i64, 500_i64)

      io = IO::Memory.new

      # Should raise when compressed size exceeds max_size
      expect_raises(BakedFileSystem::Loader::Stats::SizeExceededError) do
        stats.report_to(io, 100_i64)
      end
    end

    it "does not raise when within max_size" do
      stats = BakedFileSystem::Loader::Stats.new
      stats.add_file("/file.txt", 1000_i64, 500_i64)

      io = IO::Memory.new
      stats.report_to(io, 1000_i64) # Should not raise

      output = io.to_s
      output.should contain("BakedFileSystem: Embedded 1 file")
    end
  end

  describe "environment variable configuration" do
    it "reads BAKED_FILE_SYSTEM_MAX_SIZE from environment" do
      ENV["BAKED_FILE_SYSTEM_MAX_SIZE"] = "1000"

      stats = BakedFileSystem::Loader::Stats.new
      stats.add_file("/file.txt", 2000_i64, 1500_i64)

      io = IO::Memory.new

      expect_raises(BakedFileSystem::Loader::Stats::SizeExceededError) do
        stats.report_to(io)
      end

      ENV.delete("BAKED_FILE_SYSTEM_MAX_SIZE")
    end

    it "reads BAKED_FILE_SYSTEM_WARN_THRESHOLD from environment" do
      ENV["BAKED_FILE_SYSTEM_WARN_THRESHOLD"] = "100"

      stats = BakedFileSystem::Loader::Stats.new
      stats.add_file("/file.txt", 1000_i64, 500_i64)

      io = IO::Memory.new
      stats.report_to(io)
      output = io.to_s

      # Should warn because 500 > 100
      output.should contain("WARNING")

      ENV.delete("BAKED_FILE_SYSTEM_WARN_THRESHOLD")
    end
  end
end

describe BakedFileSystem::Loader::ByteCounter do
  it "counts bytes written through it" do
    io = IO::Memory.new
    counter = BakedFileSystem::Loader::ByteCounter.new(io)

    counter.count.should eq(0)

    counter.write("hello".to_slice)
    counter.count.should eq(5)

    counter.write(" world".to_slice)
    counter.count.should eq(11)

    io.to_s.should eq("hello world")
  end
end

describe "BakedFileSystem::Loader file filtering" do
  describe ".filter_files" do
    it "returns all files when no patterns provided" do
      files = ["src/main.cr", "src/lib.cr", "test/spec.cr"]
      result = BakedFileSystem::Loader.filter_files(files, nil, nil)
      result.should eq(files)
    end

    it "filters by include patterns only" do
      files = ["src/main.cr", "src/lib.cr", "test/spec.cr", "README.md"]
      include_patterns = ["**/*.cr"]
      result = BakedFileSystem::Loader.filter_files(files, include_patterns, nil)
      result.should eq(["src/main.cr", "src/lib.cr", "test/spec.cr"])
    end

    it "filters by exclude patterns only" do
      files = ["src/main.cr", "src/lib.cr", "test/spec.cr", "README.md"]
      exclude_patterns = ["**/test/*"]
      result = BakedFileSystem::Loader.filter_files(files, nil, exclude_patterns)
      result.should eq(["src/main.cr", "src/lib.cr", "README.md"])
    end

    it "applies include then exclude patterns" do
      files = ["src/main.cr", "src/test_helper.cr", "test/spec.cr", "README.md"]
      include_patterns = ["**/*.cr"]
      exclude_patterns = ["**/test/*", "**/*test*.cr"]
      result = BakedFileSystem::Loader.filter_files(files, include_patterns, exclude_patterns)
      result.should eq(["src/main.cr"])
    end

    it "handles multiple include patterns (OR logic)" do
      files = ["src/main.cr", "docs/guide.md", "README.txt", "config.yml"]
      include_patterns = ["**/*.cr", "**/*.md"]
      result = BakedFileSystem::Loader.filter_files(files, include_patterns, nil)
      result.should eq(["src/main.cr", "docs/guide.md"])
    end

    it "handles multiple exclude patterns (OR logic)" do
      files = ["src/main.cr", "test/spec.cr", "docs/README.md", "build/output.txt"]
      exclude_patterns = ["**/test/*", "**/build/*"]
      result = BakedFileSystem::Loader.filter_files(files, nil, exclude_patterns)
      result.should eq(["src/main.cr", "docs/README.md"])
    end

    it "returns empty array when all files filtered out" do
      files = ["test/unit.cr", "test/integration.cr"]
      exclude_patterns = ["**/test/*"]
      result = BakedFileSystem::Loader.filter_files(files, nil, exclude_patterns)
      result.should be_empty
    end

    it "handles empty file list" do
      files = [] of String
      include_patterns = ["**/*.cr"]
      result = BakedFileSystem::Loader.filter_files(files, include_patterns, nil)
      result.should be_empty
    end

    it "handles empty pattern arrays" do
      files = ["src/main.cr"]
      result = BakedFileSystem::Loader.filter_files(files, [] of String, [] of String)
      result.should eq(files)
    end
  end
end

describe "BakedFileSystem::Loader pattern matching" do
  describe ".matches_pattern?" do
    describe "with * wildcard" do
      it "matches any characters except path separator" do
        BakedFileSystem::Loader.matches_pattern?("file.txt", "*.txt").should be_true
        BakedFileSystem::Loader.matches_pattern?("test.txt", "*.txt").should be_true
        BakedFileSystem::Loader.matches_pattern?("file.cr", "*.txt").should be_false
      end

      it "matches multiple wildcards" do
        BakedFileSystem::Loader.matches_pattern?("test.spec.cr", "*.spec.*").should be_true
        BakedFileSystem::Loader.matches_pattern?("test.cr", "*.spec.*").should be_false
      end

      it "does not match across path separators" do
        BakedFileSystem::Loader.matches_pattern?("src/file.txt", "*.txt").should be_false
        BakedFileSystem::Loader.matches_pattern?("src/file.txt", "src/*.txt").should be_true
      end
    end

    describe "with ** recursive wildcard" do
      it "matches files in any subdirectory" do
        BakedFileSystem::Loader.matches_pattern?("file.cr", "**/*.cr").should be_true
        BakedFileSystem::Loader.matches_pattern?("src/file.cr", "**/*.cr").should be_true
        BakedFileSystem::Loader.matches_pattern?("src/models/user.cr", "**/*.cr").should be_true
        BakedFileSystem::Loader.matches_pattern?("file.txt", "**/*.cr").should be_false
      end

      it "matches files in specific subdirectories recursively" do
        # **/test/* means: any depth, then "test/", then any file name (no subdirs under test)
        BakedFileSystem::Loader.matches_pattern?("test/spec.cr", "**/test/*").should be_true
        BakedFileSystem::Loader.matches_pattern?("src/test/helper.cr", "**/test/*").should be_true
        BakedFileSystem::Loader.matches_pattern?("spec/unit.cr", "**/test/*").should be_false
        # For files in subdirectories of test/, use **/test/**
        BakedFileSystem::Loader.matches_pattern?("test/unit/spec.cr", "**/test/**").should be_true
      end

      it "handles ** at start of pattern" do
        BakedFileSystem::Loader.matches_pattern?("src/file.cr", "**/src/file.cr").should be_true
        BakedFileSystem::Loader.matches_pattern?("lib/src/file.cr", "**/src/file.cr").should be_true
        BakedFileSystem::Loader.matches_pattern?("file.cr", "**/file.cr").should be_true
      end

      it "handles ** at end of pattern" do
        BakedFileSystem::Loader.matches_pattern?("test/file.cr", "test/**").should be_true
        BakedFileSystem::Loader.matches_pattern?("test/unit/file.cr", "test/**").should be_true
        BakedFileSystem::Loader.matches_pattern?("spec/file.cr", "test/**").should be_false
      end
    end

    describe "with ? wildcard" do
      it "matches single character" do
        BakedFileSystem::Loader.matches_pattern?("file1.txt", "file?.txt").should be_true
        BakedFileSystem::Loader.matches_pattern?("fileA.txt", "file?.txt").should be_true
        BakedFileSystem::Loader.matches_pattern?("file12.txt", "file?.txt").should be_false
        BakedFileSystem::Loader.matches_pattern?("file.txt", "file?.txt").should be_false
      end

      it "matches multiple single characters" do
        BakedFileSystem::Loader.matches_pattern?("test_01.cr", "test_??.cr").should be_true
        BakedFileSystem::Loader.matches_pattern?("test_1.cr", "test_??.cr").should be_false
      end
    end

    describe "edge cases" do
      it "handles leading slashes consistently" do
        BakedFileSystem::Loader.matches_pattern?("/file.txt", "*.txt").should be_true
        BakedFileSystem::Loader.matches_pattern?("file.txt", "*.txt").should be_true
        BakedFileSystem::Loader.matches_pattern?("/src/file.txt", "src/*.txt").should be_true
        BakedFileSystem::Loader.matches_pattern?("src/file.txt", "src/*.txt").should be_true
      end

      it "normalizes backslashes to forward slashes" do
        BakedFileSystem::Loader.matches_pattern?("src\\file.txt", "src/*.txt").should be_true
        BakedFileSystem::Loader.matches_pattern?("src/file.txt", "src\\*.txt").should be_true
      end

      it "handles exact matches" do
        BakedFileSystem::Loader.matches_pattern?("exact.txt", "exact.txt").should be_true
        BakedFileSystem::Loader.matches_pattern?("other.txt", "exact.txt").should be_false
      end

      it "handles empty components correctly" do
        BakedFileSystem::Loader.matches_pattern?("file.txt", "**/*.txt").should be_true
      end
    end

    describe "complex patterns" do
      it "combines multiple wildcards" do
        BakedFileSystem::Loader.matches_pattern?("src/models/user_model.cr", "**/models/*.cr").should be_true
        BakedFileSystem::Loader.matches_pattern?("lib/src/models/base.cr", "**/models/*.cr").should be_true
        BakedFileSystem::Loader.matches_pattern?("src/controllers/user.cr", "**/models/*.cr").should be_false
      end

      it "matches typical exclusion patterns" do
        BakedFileSystem::Loader.matches_pattern?("spec/unit_spec.cr", "**/spec/*").should be_true
        BakedFileSystem::Loader.matches_pattern?("test/test.cr", "**/test/*").should be_true
        BakedFileSystem::Loader.matches_pattern?("src/main.cr", "**/test/*").should be_false
        # For deep paths under test/, use **
        BakedFileSystem::Loader.matches_pattern?("test/integration/test.cr", "**/test/**").should be_true
      end
    end
  end
end
