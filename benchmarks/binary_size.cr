require "json"

# Binary Size Analysis for BakedFileSystem vs Baseline
# Measures compiled binary sizes and compression overhead

module BinarySizeBenchmark
  BASELINE_DIR = File.expand_path("baseline", __DIR__)
  BAKED_DIR = File.expand_path("baked", __DIR__)
  PUBLIC_DIR = File.expand_path("public", __DIR__)
  RESULTS_FILE = File.expand_path("results/binary_size.json", __DIR__)

  struct BinaryInfo
    include JSON::Serializable

    property binary_bytes : Int64
    property binary_mb : Float64

    def initialize(@binary_bytes, @binary_mb)
    end
  end

  struct BakedBinaryInfo
    include JSON::Serializable

    property binary_bytes : Int64
    property binary_mb : Float64
    property assets_bytes : Int64
    property assets_mb : Float64
    property overhead_bytes : Int64
    property overhead_mb : Float64
    property overhead_factor : Float64
    property compression_ratio : Float64

    def initialize(@binary_bytes, @binary_mb, @assets_bytes, @assets_mb,
                   @overhead_bytes, @overhead_mb, @overhead_factor, @compression_ratio)
    end
  end

  struct BenchmarkResults
    include JSON::Serializable

    property timestamp : String
    property crystal_version : String
    property baseline : BinaryInfo
    property baked : BakedBinaryInfo

    def initialize(@timestamp, @crystal_version, @baseline, @baked)
    end
  end

  def self.get_crystal_version : String
    output = IO::Memory.new
    Process.run("crystal", ["--version"], output: output)
    output.to_s.lines.first.strip
  end

  def self.compile_if_needed(dir : String)
    app_name = File.basename(dir)
    binary_path = File.join(dir, app_name)

    unless File.exists?(binary_path)
      puts "  Compiling #{app_name}..."
      Process.run("shards", ["install"], chdir: dir, output: Process::Redirect::Close, error: Process::Redirect::Close)
      error_output = IO::Memory.new
      result = Process.run(
        "crystal",
        ["build", "#{app_name}.cr", "--release", "-o", app_name],
        chdir: dir,
        output: Process::Redirect::Close,
        error: error_output
      )

      unless result.success?
        STDERR.puts "ERROR: Compilation failed for #{app_name}"
        STDERR.puts error_output.to_s
        exit(1)
      end
    end
  end

  def self.get_binary_size(dir : String) : Int64
    app_name = File.basename(dir)
    binary_path = File.join(dir, app_name)
    File.size(binary_path)
  end

  def self.calculate_assets_size(dir : String) : Int64
    total = 0_i64
    Dir.glob(File.join(dir, "*")).each do |file|
      total += File.size(file) if File.file?(file)
    end
    total
  end

  def self.bytes_to_mb(bytes : Int64) : Float64
    bytes / (1024.0 * 1024.0)
  end

  def self.run
    puts "=" * 60
    puts "BakedFileSystem Binary Size Benchmark"
    puts "=" * 60
    puts "Crystal: #{get_crystal_version}"
    puts ""

    # Compile both apps if needed
    puts "Ensuring binaries are compiled..."
    compile_if_needed(BASELINE_DIR)
    compile_if_needed(BAKED_DIR)
    puts ""

    # Get baseline binary size
    baseline_bytes = get_binary_size(BASELINE_DIR)
    baseline_mb = bytes_to_mb(baseline_bytes)

    puts "Baseline Binary:"
    puts "  Size: #{baseline_mb.round(2)} MB (#{baseline_bytes} bytes)"
    puts ""

    # Get baked binary size and asset size
    baked_bytes = get_binary_size(BAKED_DIR)
    baked_mb = bytes_to_mb(baked_bytes)

    assets_bytes = calculate_assets_size(PUBLIC_DIR)
    assets_mb = bytes_to_mb(assets_bytes)

    # Calculate overhead (difference between baked and baseline)
    overhead_bytes = baked_bytes - baseline_bytes
    overhead_mb = bytes_to_mb(overhead_bytes)

    # Compression overhead factor (embedded size / raw asset size)
    overhead_factor = overhead_bytes.to_f / assets_bytes.to_f

    # Compression ratio (how much space assets take in binary vs raw)
    compression_ratio = overhead_bytes.to_f / assets_bytes.to_f

    puts "Baked Binary:"
    puts "  Size: #{baked_mb.round(2)} MB (#{baked_bytes} bytes)"
    puts ""

    puts "Assets:"
    puts "  Raw Size: #{assets_mb.round(2)} MB (#{assets_bytes} bytes)"
    puts "  Embedded Overhead: #{overhead_mb.round(2)} MB (#{overhead_bytes} bytes)"
    puts "  Overhead Factor: #{overhead_factor.round(2)}x"
    puts "  Compression Ratio: #{compression_ratio.round(2)}x"
    puts ""

    # Create results
    baseline_info = BinaryInfo.new(
      binary_bytes: baseline_bytes,
      binary_mb: baseline_mb
    )

    baked_info = BakedBinaryInfo.new(
      binary_bytes: baked_bytes,
      binary_mb: baked_mb,
      assets_bytes: assets_bytes,
      assets_mb: assets_mb,
      overhead_bytes: overhead_bytes,
      overhead_mb: overhead_mb,
      overhead_factor: overhead_factor,
      compression_ratio: compression_ratio
    )

    results = BenchmarkResults.new(
      timestamp: Time.utc.to_s,
      crystal_version: get_crystal_version,
      baseline: baseline_info,
      baked: baked_info
    )

    # Save results
    File.write(RESULTS_FILE, results.to_pretty_json)

    puts "Results saved to: #{RESULTS_FILE}"
    puts "=" * 60
    puts ""
    puts "Key Findings:"
    if compression_ratio < 1.0
      puts "  ✓ Assets are compressed to #{(compression_ratio * 100).round(1)}% of original size"
    else
      puts "  ⚠ Assets expanded to #{compression_ratio.round(2)}x original size (already compressed?)"
    end
    puts "  ✓ Binary size increased by #{overhead_mb.round(2)} MB"
    puts "  ✓ Overhead factor: #{overhead_factor.round(2)}x asset size"
    puts "=" * 60
  end
end

BinarySizeBenchmark.run
