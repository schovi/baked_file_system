require "json"
require "http/client"

# Memory Usage Benchmarking for BakedFileSystem vs Baseline
# Measures RSS (Resident Set Size) at various stages

module MemoryBenchmark
  BASELINE_DIR = File.expand_path("baseline", __DIR__)
  BAKED_DIR = File.expand_path("baked", __DIR__)
  RESULTS_FILE = File.expand_path("results/memory.json", __DIR__)
  BASELINE_PORT = 3000
  BAKED_PORT = 3001
  WARMUP_DELAY = 2 # seconds to wait for server startup

  struct MemoryProfile
    include JSON::Serializable

    property startup_rss_mb : Float64
    property after_small_file_mb : Float64
    property after_medium_file_mb : Float64
    property after_large_file_mb : Float64
    property after_gc_mb : Float64
    property peak_mb : Float64
    property measurements : Array(Float64)

    def initialize(@startup_rss_mb, @after_small_file_mb, @after_medium_file_mb,
                   @after_large_file_mb, @after_gc_mb, @peak_mb, @measurements)
    end
  end

  struct BenchmarkResults
    include JSON::Serializable

    property timestamp : String
    property crystal_version : String
    property baseline : MemoryProfile
    property baked : MemoryProfile
    property overhead_startup_mb : Float64
    property overhead_peak_mb : Float64

    def initialize(@timestamp, @crystal_version, @baseline, @baked,
                   @overhead_startup_mb, @overhead_peak_mb)
    end
  end

  def self.get_crystal_version : String
    output = IO::Memory.new
    Process.run("crystal", ["--version"], output: output)
    output.to_s.lines.first.strip
  end

  def self.get_rss_mb(pid : Int64) : Float64?
    # Use ps command to get RSS in KB, then convert to MB
    output = IO::Memory.new
    result = Process.run("ps", ["-o", "rss=", "-p", pid.to_s], output: output, error: Process::Redirect::Close)

    return nil unless result.success?

    rss_kb = output.to_s.strip.to_i64?
    return nil unless rss_kb

    rss_kb / 1024.0 # Convert KB to MB
  end

  def self.wait_for_server(port : Int32, timeout : Int32 = 10)
    start = Time.monotonic
    loop do
      begin
        HTTP::Client.get("http://localhost:#{port}/")
        return true
      rescue
        if (Time.monotonic - start).total_seconds > timeout
          return false
        end
        sleep 0.1
      end
    end
  end

  def self.trigger_gc(port : Int32)
    # Make a request and wait a bit to allow GC to run
    begin
      HTTP::Client.get("http://localhost:#{port}/files/small.txt")
    rescue
    end
    sleep 0.5
  end

  def self.profile_server(name : String, dir : String, port : Int32) : MemoryProfile
    app_name = File.basename(dir)
    binary_path = File.join(dir, app_name)

    puts "\nProfiling #{name}..."

    # Start server process
    puts "  Starting server on port #{port}..."
    process = Process.new(
      binary_path,
      output: Process::Redirect::Close,
      error: Process::Redirect::Close,
      chdir: dir
    )

    pid = process.pid

    # Wait for server to start
    unless wait_for_server(port)
      process.signal(Signal::TERM)
      process.wait
      raise "Server failed to start on port #{port}"
    end

    sleep WARMUP_DELAY
    measurements = [] of Float64

    # Measure startup RSS
    startup_rss = get_rss_mb(pid)
    raise "Failed to get RSS for pid #{pid}" unless startup_rss
    measurements << startup_rss
    puts "  Startup RSS: #{startup_rss.round(2)} MB"

    # Access small file
    HTTP::Client.get("http://localhost:#{port}/files/small.txt")
    sleep 0.2
    after_small = get_rss_mb(pid)
    raise "Failed to get RSS" unless after_small
    measurements << after_small
    puts "  After small file: #{after_small.round(2)} MB"

    # Access medium file
    HTTP::Client.get("http://localhost:#{port}/files/medium.json")
    sleep 0.2
    after_medium = get_rss_mb(pid)
    raise "Failed to get RSS" unless after_medium
    measurements << after_medium
    puts "  After medium file: #{after_medium.round(2)} MB"

    # Access large file
    HTTP::Client.get("http://localhost:#{port}/files/large.dat")
    sleep 0.2
    after_large = get_rss_mb(pid)
    raise "Failed to get RSS" unless after_large
    measurements << after_large
    puts "  After large file: #{after_large.round(2)} MB"

    # Trigger GC and measure
    trigger_gc(port)
    GC.collect # Suggest GC in benchmark process too
    sleep 1
    after_gc = get_rss_mb(pid)
    raise "Failed to get RSS" unless after_gc
    measurements << after_gc
    puts "  After GC: #{after_gc.round(2)} MB"

    # Stop server
    process.signal(Signal::TERM)
    process.wait

    MemoryProfile.new(
      startup_rss_mb: startup_rss,
      after_small_file_mb: after_small,
      after_medium_file_mb: after_medium,
      after_large_file_mb: after_large,
      after_gc_mb: after_gc,
      peak_mb: measurements.max,
      measurements: measurements
    )
  rescue ex
    # Ensure process is killed on error
    begin
      process.try &.signal(Signal::KILL)
      process.try &.wait
    rescue
    end
    raise ex
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

  def self.kill_existing_servers
    # Kill any existing processes on the ports
    [BASELINE_PORT, BAKED_PORT].each do |port|
      Process.run("lsof", ["-ti:#{port}"], output: Process::Redirect::Pipe, error: Process::Redirect::Close) do |proc|
        pids = proc.output.gets_to_end.strip
        unless pids.empty?
          pids.split("\n").each do |pid|
            Process.run("kill", ["-9", pid], output: Process::Redirect::Close, error: Process::Redirect::Close)
          end
        end
      end
    end
    sleep 1
  end

  def self.run
    puts "=" * 60
    puts "BakedFileSystem Memory Usage Benchmark"
    puts "=" * 60
    puts "Crystal: #{get_crystal_version}"
    puts ""

    # Ensure binaries are compiled
    puts "Ensuring binaries are compiled..."
    compile_if_needed(BASELINE_DIR)
    compile_if_needed(BAKED_DIR)

    # Kill any existing servers
    puts "Cleaning up existing servers..."
    kill_existing_servers

    # Profile baseline
    baseline_profile = profile_server("Baseline (File I/O)", BASELINE_DIR, BASELINE_PORT)

    # Wait a bit between tests
    sleep 2

    # Profile baked
    baked_profile = profile_server("Baked (BakedFileSystem)", BAKED_DIR, BAKED_PORT)

    # Calculate overhead
    overhead_startup = baked_profile.startup_rss_mb - baseline_profile.startup_rss_mb
    overhead_peak = baked_profile.peak_mb - baseline_profile.peak_mb

    # Create results
    results = BenchmarkResults.new(
      timestamp: Time.utc.to_s,
      crystal_version: get_crystal_version,
      baseline: baseline_profile,
      baked: baked_profile,
      overhead_startup_mb: overhead_startup,
      overhead_peak_mb: overhead_peak
    )

    # Save results
    File.write(RESULTS_FILE, results.to_pretty_json)

    puts "\n" + "=" * 60
    puts "Memory Overhead Summary"
    puts "=" * 60
    puts "Startup Memory Overhead: #{overhead_startup.round(2)} MB"
    puts "Peak Memory Overhead: #{overhead_peak.round(2)} MB"
    puts ""
    puts "Results saved to: #{RESULTS_FILE}"
    puts "=" * 60
  end
end

MemoryBenchmark.run
