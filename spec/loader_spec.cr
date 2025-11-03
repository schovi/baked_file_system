require "./spec_helper"
require "../src/loader/loader"
require "../src/loader/stats"
require "../src/loader/byte_counter"

describe BakedFileSystem::Loader do
  it "raises if path does not exist" do
    expect_raises BakedFileSystem::Loader::Error, "path does not exist" do
      BakedFileSystem::Loader.load(IO::Memory.new, File.expand_path(File.join(__DIR__, "invalid_path")))
    end
  end

  describe "size tracking and reporting" do
    it "accepts max_size parameter" do
      stdout = IO::Memory.new

      # Should complete successfully with a large max_size
      BakedFileSystem::Loader.load(stdout, File.expand_path(File.join(__DIR__, "storage")), false, 10_000_000_i64)

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
      stats.report_to(io, 1000_i64)  # Should not raise

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
