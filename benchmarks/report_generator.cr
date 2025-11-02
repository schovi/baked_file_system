require "json"

# Report Generator for BakedFileSystem Benchmarks
# Aggregates all benchmark results into a comprehensive markdown report

module ReportGenerator
  RESULTS_DIR = File.expand_path("results", __DIR__)
  REPORT_FILE = File.expand_path("results/REPORT.md", __DIR__)

  # Import result structures (simplified for JSON parsing)
  alias CompileTimeResults = JSON::Any
  alias BinarySizeResults = JSON::Any
  alias MemoryResults = JSON::Any
  alias PerformanceResults = JSON::Any

  def self.load_json(filename : String) : JSON::Any?
    path = File.join(RESULTS_DIR, filename)
    return nil unless File.exists?(path)
    JSON.parse(File.read(path))
  rescue
    nil
  end

  def self.get_system_info : String
    os_info = `uname -s`.strip
    os_version = `uname -r`.strip
    arch = `uname -m`.strip
    cpu_info = ""

    # Try to get CPU info (macOS)
    if os_info == "Darwin"
      cpu_info = `sysctl -n machdep.cpu.brand_string 2>/dev/null`.strip
    end

    "#{os_info} #{os_version} (#{arch})#{cpu_info.empty? ? "" : " - #{cpu_info}"}"
  end

  def self.format_table_row(*columns)
    "| " + columns.join(" | ") + " |"
  end

  def self.format_table_separator(count : Int32)
    "| " + (["---"] * count).join(" | ") + " |"
  end

  def self.ascii_bar(value : Float64, max : Float64, width : Int32 = 40) : String
    filled = ((value / max) * width).to_i
    "█" * filled + "░" * (width - filled)
  end

  def self.generate_compile_time_section(data : JSON::Any) : String
    String.build do |str|
      str << "## Compile Time Benchmarks\n\n"

      baseline = data["baseline"]
      baked = data["baked"]
      overhead = data["overhead_seconds"].as_f
      percent = data["overhead_percent"].as_f

      str << "**Test Parameters:**\n"
      str << "- Iterations: #{data["iterations"]}\n"
      str << "- Crystal: #{data["crystal_version"]}\n\n"

      str << "**Results:**\n\n"
      str << format_table_row("Configuration", "Mean (s)", "Std Dev (s)", "Min (s)", "Max (s)")
      str << "\n"
      str << format_table_separator(5)
      str << "\n"
      str << format_table_row(
        "Baseline",
        baseline["mean"].as_f.round(2).to_s,
        baseline["std_dev"].as_f.round(2).to_s,
        baseline["min"].as_f.round(2).to_s,
        baseline["max"].as_f.round(2).to_s
      )
      str << "\n"
      str << format_table_row(
        "BakedFileSystem",
        baked["mean"].as_f.round(2).to_s,
        baked["std_dev"].as_f.round(2).to_s,
        baked["min"].as_f.round(2).to_s,
        baked["max"].as_f.round(2).to_s
      )
      str << "\n\n"

      str << "**Overhead:**\n"
      str << "- Absolute: #{overhead.round(2)}s\n"
      str << "- Relative: #{percent.round(1)}%\n\n"

      # Visual comparison
      max_time = [baseline["mean"].as_f, baked["mean"].as_f].max
      str << "**Visual Comparison:**\n"
      str << "```\n"
      str << "Baseline:        #{ascii_bar(baseline["mean"].as_f, max_time)} #{baseline["mean"].as_f.round(2)}s\n"
      str << "BakedFileSystem: #{ascii_bar(baked["mean"].as_f, max_time)} #{baked["mean"].as_f.round(2)}s\n"
      str << "```\n\n"
    end
  end

  def self.generate_binary_size_section(data : JSON::Any) : String
    String.build do |str|
      str << "## Binary Size Analysis\n\n"

      baseline = data["baseline"]
      baked = data["baked"]

      str << "**Results:**\n\n"
      str << format_table_row("Metric", "Baseline", "BakedFileSystem", "Difference")
      str << "\n"
      str << format_table_separator(4)
      str << "\n"
      str << format_table_row(
        "Binary Size",
        "#{baseline["binary_mb"].as_f.round(2)} MB",
        "#{baked["binary_mb"].as_f.round(2)} MB",
        "+#{baked["overhead_mb"].as_f.round(2)} MB"
      )
      str << "\n"
      str << format_table_row(
        "Asset Size",
        "N/A",
        "#{baked["assets_mb"].as_f.round(2)} MB (raw)",
        "-"
      )
      str << "\n\n"

      str << "**Compression Analysis:**\n"
      str << "- Raw assets: #{baked["assets_mb"].as_f.round(2)} MB\n"
      str << "- Embedded overhead: #{baked["overhead_mb"].as_f.round(2)} MB\n"
      str << "- Compression ratio: #{baked["compression_ratio"].as_f.round(2)}x\n"
      str << "- Overhead factor: #{baked["overhead_factor"].as_f.round(2)}x asset size\n\n"

      # Visual comparison
      str << "**Visual Comparison:**\n"
      str << "```\n"
      max_size = baked["binary_mb"].as_f
      str << "Baseline:        #{ascii_bar(baseline["binary_mb"].as_f, max_size)} #{baseline["binary_mb"].as_f.round(2)} MB\n"
      str << "BakedFileSystem: #{ascii_bar(baked["binary_mb"].as_f, max_size)} #{baked["binary_mb"].as_f.round(2)} MB\n"
      str << "Assets (raw):    #{ascii_bar(baked["assets_mb"].as_f, max_size)} #{baked["assets_mb"].as_f.round(2)} MB\n"
      str << "```\n\n"
    end
  end

  def self.generate_memory_section(data : JSON::Any) : String
    String.build do |str|
      str << "## Memory Usage Benchmarks\n\n"

      baseline = data["baseline"]
      baked = data["baked"]

      str << "**Memory Profile (RSS in MB):**\n\n"
      str << format_table_row("Stage", "Baseline", "BakedFileSystem", "Overhead")
      str << "\n"
      str << format_table_separator(4)
      str << "\n"

      stages = [
        {"Startup", "startup_rss_mb"},
        {"After Small File", "after_small_file_mb"},
        {"After Medium File", "after_medium_file_mb"},
        {"After Large File", "after_large_file_mb"},
        {"After GC", "after_gc_mb"},
        {"Peak", "peak_mb"},
      ]

      stages.each do |(name, key)|
        baseline_val = baseline[key].as_f
        baked_val = baked[key].as_f
        overhead = baked_val - baseline_val

        str << format_table_row(
          name,
          baseline_val.round(2).to_s,
          baked_val.round(2).to_s,
          overhead > 0 ? "+#{overhead.round(2)}" : overhead.round(2).to_s
        )
        str << "\n"
      end

      str << "\n**Summary:**\n"
      str << "- Startup overhead: #{data["overhead_startup_mb"].as_f.round(2)} MB\n"
      str << "- Peak overhead: #{data["overhead_peak_mb"].as_f.round(2)} MB\n\n"

      # Visual comparison
      max_mem = [baseline["peak_mb"].as_f, baked["peak_mb"].as_f].max
      str << "**Peak Memory Comparison:**\n"
      str << "```\n"
      str << "Baseline:        #{ascii_bar(baseline["peak_mb"].as_f, max_mem)} #{baseline["peak_mb"].as_f.round(2)} MB\n"
      str << "BakedFileSystem: #{ascii_bar(baked["peak_mb"].as_f, max_mem)} #{baked["peak_mb"].as_f.round(2)} MB\n"
      str << "```\n\n"
    end
  end

  def self.generate_performance_section(data : JSON::Any) : String
    String.build do |str|
      str << "## Performance Benchmarks\n\n"

      str << "**Test Parameters:**\n"
      str << "- Warmup: #{data["warmup_requests"]} requests\n"
      str << "- Benchmark: #{data["benchmark_requests"]} requests\n"
      str << "- Concurrent Clients: #{data["concurrent_clients"]}\n\n"

      files = [
        {"Small File (1KB)", "small_file"},
        {"Medium File (100KB)", "medium_file"},
        {"Large File (1MB)", "large_file"},
      ]

      files.each do |(name, key)|
        file_data = data[key]
        baseline = file_data["baseline"]
        baked = file_data["baked"]

        str << "### #{name}\n\n"

        str << format_table_row("Metric", "Baseline", "BakedFileSystem", "Improvement")
        str << "\n"
        str << format_table_separator(4)
        str << "\n"

        metrics = [
          {"Mean Latency", "mean_ms", "ms"},
          {"Median Latency", "median_ms", "ms"},
          {"P95 Latency", "p95_ms", "ms"},
          {"P99 Latency", "p99_ms", "ms"},
          {"Throughput", "requests_per_second", "req/s"},
        ]

        metrics.each do |(metric_name, metric_key, unit)|
          baseline_val = baseline[metric_key].as_f
          baked_val = baked[metric_key].as_f

          # For latency (lower is better), for throughput (higher is better)
          if metric_key == "requests_per_second"
            improvement = ((baked_val - baseline_val) / baseline_val) * 100
            improvement_str = improvement > 0 ? "+#{improvement.round(1)}%" : "#{improvement.round(1)}%"
          else
            improvement = ((baseline_val - baked_val) / baseline_val) * 100
            improvement_str = improvement > 0 ? "-#{improvement.round(1)}%" : "#{improvement.round(1)}%"
          end

          str << format_table_row(
            metric_name,
            "#{baseline_val.round(2)} #{unit}",
            "#{baked_val.round(2)} #{unit}",
            improvement_str
          )
          str << "\n"
        end

        str << "\n**Speedup: #{file_data["speedup_factor"].as_f.round(2)}x**\n\n"

        # Visual comparison
        max_latency = baseline["mean_ms"].as_f
        str << "**Mean Latency Comparison:**\n"
        str << "```\n"
        str << "Baseline:        #{ascii_bar(baseline["mean_ms"].as_f, max_latency)} #{baseline["mean_ms"].as_f.round(2)} ms\n"
        str << "BakedFileSystem: #{ascii_bar(baked["mean_ms"].as_f, max_latency)} #{baked["mean_ms"].as_f.round(2)} ms\n"
        str << "```\n\n"
      end
    end
  end

  def self.generate_report
    puts "Generating benchmark report..."

    # Load all results
    compile_data = load_json("compile_time.json")
    binary_data = load_json("binary_size.json")
    memory_data = load_json("memory.json")
    performance_data = load_json("performance.json")

    # Check if we have any data
    if compile_data.nil? && binary_data.nil? && memory_data.nil? && performance_data.nil?
      STDERR.puts "ERROR: No benchmark result files found in #{RESULTS_DIR}"
      STDERR.puts "Please run the benchmarks first."
      exit(1)
    end

    # Generate report
    report = String.build do |str|
      str << "# BakedFileSystem Performance Benchmarks\n\n"

      str << "**Generated:** #{Time.utc.to_s("%Y-%m-%d %H:%M:%S UTC")}\n\n"

      # Executive Summary
      str << "## Executive Summary\n\n"

      str << "This report presents comprehensive benchmarking results comparing BakedFileSystem "
      str << "(compile-time asset embedding) against traditional File I/O approaches. "
      str << "The benchmarks measure compile time overhead, binary size impact, memory usage, "
      str << "and runtime performance.\n\n"

      str << "**Key Findings:**\n\n"

      if compile_data
        overhead_pct = compile_data["overhead_percent"].as_f
        str << "- **Compile Time**: #{overhead_pct.round(1)}% overhead for asset embedding\n"
      end

      if binary_data
        compression = binary_data["baked"]["compression_ratio"].as_f
        str << "- **Binary Size**: #{compression.round(2)}x compression ratio (assets compressed to #{(compression * 100).round(1)}% of original size)\n"
      end

      if memory_data
        mem_overhead = memory_data["overhead_startup_mb"].as_f
        str << "- **Memory Usage**: #{mem_overhead.round(2)} MB startup overhead\n"
      end

      if performance_data
        small_speedup = performance_data["small_file"]["speedup_factor"].as_f
        str << "- **Performance**: #{small_speedup.round(2)}x faster for small files\n"
      end

      str << "\n---\n\n"

      # System Specifications
      str << "## System Specifications\n\n"
      str << "- **OS**: #{get_system_info}\n"

      if compile_data
        str << "- **Crystal**: #{compile_data["crystal_version"]}\n"
      end

      str << "- **Test Date**: #{Time.utc.to_s("%Y-%m-%d")}\n\n"

      str << "---\n\n"

      # Methodology
      str << "## Methodology\n\n"
      str << "All benchmarks compare two identical Kemal web applications:\n\n"
      str << "1. **Baseline**: Traditional File I/O using `send_file`\n"
      str << "2. **BakedFileSystem**: Compile-time asset embedding with `bake_folder`\n\n"
      str << "Both applications serve the same test assets:\n"
      str << "- `small.txt`: ~1 KB text file\n"
      str << "- `medium.json`: ~100 KB JSON file\n"
      str << "- `large.dat`: ~1 MB binary file\n\n"

      str << "---\n\n"

      # Individual sections
      str << generate_compile_time_section(compile_data) if compile_data
      str << "---\n\n"

      str << generate_binary_size_section(binary_data) if binary_data
      str << "---\n\n"

      str << generate_memory_section(memory_data) if memory_data
      str << "---\n\n"

      str << generate_performance_section(performance_data) if performance_data
      str << "---\n\n"

      # Conclusions
      str << "## Conclusions\n\n"

      str << "### When to Use BakedFileSystem\n\n"
      str << "**Recommended for:**\n"
      str << "- Applications with small to medium-sized static assets (< 10 MB)\n"
      str << "- Scenarios requiring maximum performance for static file serving\n"
      str << "- Single-binary deployments where simplicity is valued\n"
      str << "- Read-heavy workloads with frequent small file access\n\n"

      str << "**Not recommended for:**\n"
      str << "- Very large asset collections (> 50 MB) - significant compile time overhead\n"
      str << "- Frequently changing assets - requires recompilation\n"
      str << "- Memory-constrained environments - binary size increase matters\n\n"

      str << "### Trade-offs\n\n"

      if compile_data && binary_data && performance_data
        compile_overhead = compile_data["overhead_seconds"].as_f
        size_overhead = binary_data["baked"]["overhead_mb"].as_f
        small_speedup = performance_data["small_file"]["speedup_factor"].as_f

        str << "**Benefits:**\n"
        str << "- #{small_speedup.round(1)}x performance improvement for small files\n"
        str << "- Single-binary deployment (no external asset dependencies)\n"
        str << "- Automatic gzip compression reduces binary size\n\n"

        str << "**Costs:**\n"
        str << "- +#{compile_overhead.round(1)}s compilation time\n"
        str << "- +#{size_overhead.round(1)} MB binary size\n"
        str << "- Assets fixed at compile time\n\n"
      end

      str << "---\n\n"

      str << "## Appendix\n\n"
      str << "**Benchmark Scripts:**\n"
      str << "- `compile_time.cr` - Compilation time measurement\n"
      str << "- `binary_size.cr` - Binary size analysis\n"
      str << "- `memory.cr` - Runtime memory profiling\n"
      str << "- `performance.cr` - HTTP request latency and throughput\n\n"

      str << "**Raw Data:**\n"
      str << "All raw benchmark results are available in JSON format:\n"
      str << "- `results/compile_time.json`\n"
      str << "- `results/binary_size.json`\n"
      str << "- `results/memory.json`\n"
      str << "- `results/performance.json`\n\n"

      str << "---\n\n"
      str << "*Generated by BakedFileSystem benchmark suite*\n"
    end

    # Write report
    File.write(REPORT_FILE, report)

    puts "Report generated successfully!"
    puts "Location: #{REPORT_FILE}"
  end
end

ReportGenerator.generate_report
