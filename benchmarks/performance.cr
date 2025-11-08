require "json"
require "http/client"

# Performance Benchmarking for BakedFileSystem vs Baseline
# Measures request latency and throughput

module PerformanceBenchmark
  BASELINE_DIR       = File.expand_path("baseline", __DIR__)
  BAKED_DIR          = File.expand_path("baked", __DIR__)
  RESULTS_FILE       = File.expand_path("results/performance.json", __DIR__)
  BASELINE_PORT      = 3000
  BAKED_PORT         = 3001
  WARMUP_REQUESTS    =  100
  BENCHMARK_REQUESTS = 1000
  CONCURRENT_CLIENTS =   10

  struct LatencyStats
    include JSON::Serializable

    property mean_ms : Float64
    property median_ms : Float64
    property p95_ms : Float64
    property p99_ms : Float64
    property min_ms : Float64
    property max_ms : Float64
    property std_dev_ms : Float64
    property requests_per_second : Float64

    def initialize(@mean_ms, @median_ms, @p95_ms, @p99_ms, @min_ms, @max_ms, @std_dev_ms, @requests_per_second)
    end
  end

  struct FilePerformance
    include JSON::Serializable

    property baseline : LatencyStats
    property baked : LatencyStats
    property speedup_factor : Float64
    property speedup_percent : Float64

    def initialize(@baseline, @baked, @speedup_factor, @speedup_percent)
    end
  end

  struct BenchmarkResults
    include JSON::Serializable

    property timestamp : String
    property crystal_version : String
    property warmup_requests : Int32
    property benchmark_requests : Int32
    property concurrent_clients : Int32
    property small_file : FilePerformance
    property medium_file : FilePerformance
    property large_file : FilePerformance

    def initialize(@timestamp, @crystal_version, @warmup_requests, @benchmark_requests,
                   @concurrent_clients, @small_file, @medium_file, @large_file)
    end
  end

  def self.get_crystal_version : String
    output = IO::Memory.new
    Process.run("crystal", ["--version"], output: output)
    output.to_s.lines.first.strip
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
        sleep 0.1.seconds
      end
    end
  end

  def self.benchmark_endpoint(url : String, requests : Int32, concurrent : Int32 = 1) : Array(Float64)
    latencies = [] of Float64
    mutex = Mutex.new

    # Sequential benchmark
    if concurrent == 1
      requests.times do
        start = Time.monotonic
        HTTP::Client.get(url)
        duration = (Time.monotonic - start).total_milliseconds
        latencies << duration
      end
    else
      # Concurrent benchmark
      requests_per_client = requests // concurrent
      channels = Array.new(concurrent) { Channel(Array(Float64)).new }

      concurrent.times do |i|
        spawn do
          client_latencies = [] of Float64
          client = HTTP::Client.new(URI.parse(url))

          requests_per_client.times do
            start = Time.monotonic
            client.get(url)
            duration = (Time.monotonic - start).total_milliseconds
            client_latencies << duration
          end

          client.close
          channels[i].send(client_latencies)
        end
      end

      # Collect results from all clients
      concurrent.times do |i|
        client_results = channels[i].receive
        mutex.synchronize do
          latencies.concat(client_results)
        end
      end
    end

    latencies
  end

  def self.calculate_stats(latencies : Array(Float64), total_time_ms : Float64) : LatencyStats
    sorted = latencies.sort
    mean = latencies.sum / latencies.size
    median = sorted[sorted.size // 2]
    p95_index = (sorted.size * 0.95).to_i
    p99_index = (sorted.size * 0.99).to_i
    p95 = sorted[p95_index]
    p99 = sorted[p99_index]
    min = sorted.first
    max = sorted.last

    variance = latencies.map { |l| (l - mean) ** 2 }.sum / latencies.size
    std_dev = Math.sqrt(variance)

    # Calculate RPS based on total time
    rps = (latencies.size / total_time_ms) * 1000

    LatencyStats.new(
      mean_ms: mean,
      median_ms: median,
      p95_ms: p95,
      p99_ms: p99,
      min_ms: min,
      max_ms: max,
      std_dev_ms: std_dev,
      requests_per_second: rps
    )
  end

  def self.benchmark_file(file_name : String, baseline_port : Int32, baked_port : Int32) : FilePerformance
    puts "  Benchmarking #{file_name}..."

    baseline_url = "http://localhost:#{baseline_port}/files/#{file_name}"
    baked_url = "http://localhost:#{baked_port}/files/#{file_name}"

    # Warmup
    puts "    Warming up (#{WARMUP_REQUESTS} requests)..."
    benchmark_endpoint(baseline_url, WARMUP_REQUESTS)
    benchmark_endpoint(baked_url, WARMUP_REQUESTS)

    # Benchmark baseline
    puts "    Benchmarking baseline..."
    baseline_start = Time.monotonic
    baseline_latencies = benchmark_endpoint(baseline_url, BENCHMARK_REQUESTS, CONCURRENT_CLIENTS)
    baseline_total_ms = (Time.monotonic - baseline_start).total_milliseconds
    baseline_stats = calculate_stats(baseline_latencies, baseline_total_ms)

    # Benchmark baked
    puts "    Benchmarking baked..."
    baked_start = Time.monotonic
    baked_latencies = benchmark_endpoint(baked_url, BENCHMARK_REQUESTS, CONCURRENT_CLIENTS)
    baked_total_ms = (Time.monotonic - baked_start).total_milliseconds
    baked_stats = calculate_stats(baked_latencies, baked_total_ms)

    # Calculate speedup
    speedup_factor = baseline_stats.mean_ms / baked_stats.mean_ms
    speedup_percent = ((baseline_stats.mean_ms - baked_stats.mean_ms) / baseline_stats.mean_ms) * 100

    FilePerformance.new(
      baseline: baseline_stats,
      baked: baked_stats,
      speedup_factor: speedup_factor,
      speedup_percent: speedup_percent
    )
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
    sleep 1.second
  end

  def self.start_server(dir : String, port : Int32) : Process
    app_name = File.basename(dir)
    binary_path = File.join(dir, app_name)

    process = Process.new(
      binary_path,
      output: Process::Redirect::Close,
      error: Process::Redirect::Close,
      chdir: dir
    )

    unless wait_for_server(port)
      process.signal(Signal::TERM)
      process.wait
      raise "Server failed to start on port #{port}"
    end

    sleep 1.second # Additional warmup
    process
  end

  def self.run
    puts "=" * 60
    puts "BakedFileSystem Performance Benchmark"
    puts "=" * 60
    puts "Crystal: #{get_crystal_version}"
    puts "Warmup: #{WARMUP_REQUESTS} requests"
    puts "Benchmark: #{BENCHMARK_REQUESTS} requests"
    puts "Concurrent Clients: #{CONCURRENT_CLIENTS}"
    puts ""

    # Ensure binaries are compiled
    puts "Ensuring binaries are compiled..."
    compile_if_needed(BASELINE_DIR)
    compile_if_needed(BAKED_DIR)

    # Kill existing servers
    puts "Cleaning up existing servers..."
    kill_existing_servers

    # Start both servers
    puts "Starting servers..."
    baseline_process = start_server(BASELINE_DIR, BASELINE_PORT)
    baked_process = start_server(BAKED_DIR, BAKED_PORT)

    begin
      puts ""
      puts "Running benchmarks..."

      # Benchmark different file sizes
      small_perf = benchmark_file("small.txt", BASELINE_PORT, BAKED_PORT)
      medium_perf = benchmark_file("medium.json", BASELINE_PORT, BAKED_PORT)
      large_perf = benchmark_file("large.dat", BASELINE_PORT, BAKED_PORT)

      # Create results
      results = BenchmarkResults.new(
        timestamp: Time.utc.to_s,
        crystal_version: get_crystal_version,
        warmup_requests: WARMUP_REQUESTS,
        benchmark_requests: BENCHMARK_REQUESTS,
        concurrent_clients: CONCURRENT_CLIENTS,
        small_file: small_perf,
        medium_file: medium_perf,
        large_file: large_perf
      )

      # Save results
      File.write(RESULTS_FILE, results.to_pretty_json)

      # Print summary
      puts "\n" + "=" * 60
      puts "Performance Summary"
      puts "=" * 60
      puts ""

      [
        {"Small (1KB)", small_perf},
        {"Medium (100KB)", medium_perf},
        {"Large (1MB)", large_perf},
      ].each do |(name, perf)|
        puts "#{name}:"
        puts "  Baseline: #{perf.baseline.mean_ms.round(2)}ms avg, #{perf.baseline.requests_per_second.round(0)} req/s"
        puts "  Baked:    #{perf.baked.mean_ms.round(2)}ms avg, #{perf.baked.requests_per_second.round(0)} req/s"
        puts "  Speedup:  #{perf.speedup_factor.round(2)}x (#{perf.speedup_percent.round(1)}% faster)"
        puts ""
      end

      puts "Results saved to: #{RESULTS_FILE}"
      puts "=" * 60
    ensure
      # Stop servers
      puts "Stopping servers..."
      baseline_process.signal(Signal::TERM)
      baked_process.signal(Signal::TERM)
      baseline_process.wait
      baked_process.wait
    end
  end
end

PerformanceBenchmark.run
