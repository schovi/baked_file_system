require "json"
require "file_utils"

# Compile Time Benchmarking for BakedFileSystem vs Baseline
# Tests compilation time overhead of embedding assets

module CompileTimeBenchmark
  ITERATIONS   = 5
  BASELINE_DIR = File.expand_path("baseline", __DIR__)
  BAKED_DIR    = File.expand_path("baked", __DIR__)
  RESULTS_FILE = File.expand_path("results/compile_time.json", __DIR__)

  struct CompileResult
    include JSON::Serializable

    property mean : Float64
    property std_dev : Float64
    property min : Float64
    property max : Float64
    property runs : Array(Float64)

    def initialize(@mean, @std_dev, @min, @max, @runs)
    end
  end

  struct BenchmarkResults
    include JSON::Serializable

    property timestamp : String
    property crystal_version : String
    property iterations : Int32
    property baseline : CompileResult
    property baked : CompileResult
    property overhead_seconds : Float64
    property overhead_percent : Float64

    def initialize(@timestamp, @crystal_version, @iterations, @baseline, @baked, @overhead_seconds, @overhead_percent)
    end
  end

  def self.clean_build(dir : String)
    puts "  Cleaning build artifacts in #{File.basename(dir)}..."

    # Remove binary
    binary = File.join(dir, File.basename(dir))
    File.delete(binary) if File.exists?(binary)

    # Remove shard.lock and lib/ to force full rebuild
    shard_lock = File.join(dir, "shard.lock")
    File.delete(shard_lock) if File.exists?(shard_lock)

    lib_dir = File.join(dir, "lib")
    FileUtils.rm_rf(lib_dir) if Dir.exists?(lib_dir)

    # Clean Crystal cache
    Process.run("crystal", ["clear_cache"], chdir: dir, output: Process::Redirect::Close, error: Process::Redirect::Close)
  end

  def self.compile_app(dir : String) : Float64
    app_name = File.basename(dir)

    # First install dependencies (not counted in compile time)
    Process.run("shards", ["install"], chdir: dir, output: Process::Redirect::Close, error: Process::Redirect::Close)

    # Measure compilation time
    start = Time.monotonic
    error_output = IO::Memory.new
    result = Process.run(
      "crystal",
      ["build", "#{app_name}.cr", "--release", "-o", app_name],
      chdir: dir,
      output: Process::Redirect::Close,
      error: error_output
    )
    duration = (Time.monotonic - start).total_seconds

    unless result.success?
      STDERR.puts "ERROR: Compilation failed for #{app_name}"
      STDERR.puts error_output.to_s
      exit(1)
    end

    duration
  end

  def self.run_benchmark(name : String, dir : String) : Array(Float64)
    puts "\nBenchmarking #{name}..."
    times = [] of Float64

    ITERATIONS.times do |i|
      puts "  Run #{i + 1}/#{ITERATIONS}..."
      clean_build(dir)
      time = compile_app(dir)
      times << time
      puts "    Time: #{time.round(2)}s"
    end

    times
  end

  def self.calculate_stats(times : Array(Float64)) : CompileResult
    mean = times.sum / times.size
    variance = times.map { |t| (t - mean) ** 2 }.sum / times.size
    std_dev = Math.sqrt(variance)

    CompileResult.new(
      mean: mean,
      std_dev: std_dev,
      min: times.min,
      max: times.max,
      runs: times
    )
  end

  def self.get_crystal_version : String
    output = IO::Memory.new
    Process.run("crystal", ["--version"], output: output)
    output.to_s.lines.first.strip
  end

  def self.run
    puts "=" * 60
    puts "BakedFileSystem Compile Time Benchmark"
    puts "=" * 60
    puts "Iterations: #{ITERATIONS}"
    puts "Crystal: #{get_crystal_version}"
    puts ""

    # Benchmark baseline
    baseline_times = run_benchmark("Baseline (File I/O)", BASELINE_DIR)
    baseline_stats = calculate_stats(baseline_times)

    # Benchmark baked
    baked_times = run_benchmark("Baked (BakedFileSystem)", BAKED_DIR)
    baked_stats = calculate_stats(baked_times)

    # Calculate overhead
    overhead_seconds = baked_stats.mean - baseline_stats.mean
    overhead_percent = (overhead_seconds / baseline_stats.mean) * 100

    # Create results
    results = BenchmarkResults.new(
      timestamp: Time.utc.to_s,
      crystal_version: get_crystal_version,
      iterations: ITERATIONS,
      baseline: baseline_stats,
      baked: baked_stats,
      overhead_seconds: overhead_seconds,
      overhead_percent: overhead_percent
    )

    # Save results
    File.write(RESULTS_FILE, results.to_pretty_json)
    puts "\n" + "=" * 60
    puts "Results Summary"
    puts "=" * 60
    puts "Baseline (File I/O):"
    puts "  Mean:    #{baseline_stats.mean.round(2)}s"
    puts "  Std Dev: #{baseline_stats.std_dev.round(2)}s"
    puts "  Range:   #{baseline_stats.min.round(2)}s - #{baseline_stats.max.round(2)}s"
    puts ""
    puts "Baked (BakedFileSystem):"
    puts "  Mean:    #{baked_stats.mean.round(2)}s"
    puts "  Std Dev: #{baked_stats.std_dev.round(2)}s"
    puts "  Range:   #{baked_stats.min.round(2)}s - #{baked_stats.max.round(2)}s"
    puts ""
    puts "Compilation Overhead:"
    puts "  Absolute: #{overhead_seconds.round(2)}s"
    puts "  Relative: #{overhead_percent.round(1)}%"
    puts ""
    puts "Results saved to: #{RESULTS_FILE}"
    puts "=" * 60
  end
end

CompileTimeBenchmark.run
