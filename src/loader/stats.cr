module BakedFileSystem
  module Loader
    class Stats
      property file_count : Int32 = 0
      property total_uncompressed : Int64 = 0
      property total_compressed : Int64 = 0
      property large_files : Array({String, Int64, Int64}) = [] of {String, Int64, Int64}

      DEFAULT_MAX_SIZE          = 52_428_800_i64 # 50 MB
      DEFAULT_WARN_THRESHOLD    = 10_485_760_i64 # 10 MB
      LARGE_FILE_WARN_THRESHOLD =  1_048_576_i64 #  1 MB

      def initialize
        @max_size = parse_env_size("BAKED_FILE_SYSTEM_MAX_SIZE") || DEFAULT_MAX_SIZE
        @warn_threshold = parse_env_size("BAKED_FILE_SYSTEM_WARN_THRESHOLD") || DEFAULT_WARN_THRESHOLD
      end

      def add_file(path : String, uncompressed_size : Int64, compressed_size : Int64)
        @file_count += 1
        @total_uncompressed += uncompressed_size
        @total_compressed += compressed_size

        if compressed_size >= LARGE_FILE_WARN_THRESHOLD
          @large_files << {path, uncompressed_size, compressed_size}
        end
      end

      class SizeExceededError < Exception
      end

      def report_to(io : IO, max_size_override : Int64? = nil)
        effective_max_size = max_size_override || @max_size

        io.puts "BakedFileSystem: Embedded #{file_count} file#{"s" if file_count != 1} (#{human_size(total_uncompressed)} → #{human_size(total_compressed)} compressed, #{compression_ratio}% ratio)"

        if large_files.any?
          io.puts ""
          large_files.each do |(path, uncompressed, compressed)|
            io.puts "⚠️  WARNING: Large file detected: #{path} (#{human_size(uncompressed)} → #{human_size(compressed)})"
          end
        end

        if total_compressed >= @warn_threshold
          io.puts ""
          io.puts "⚠️  WARNING: Total embedded size (#{human_size(total_compressed)}) is significant."
          io.puts "    Consider using lazy loading or external storage for large assets."
        end

        if total_compressed > effective_max_size
          io.puts ""
          io.puts "❌  ERROR: Total embedded size (#{human_size(total_compressed)}) exceeds limit (#{human_size(effective_max_size)})"
          io.puts "    Reduce the number/size of embedded files or increase the limit."
          raise SizeExceededError.new("Total size #{human_size(total_compressed)} exceeds limit #{human_size(effective_max_size)}")
        end
      end

      def compression_ratio : Float64
        return 0.0 if total_uncompressed == 0
        ((total_compressed.to_f / total_uncompressed) * 100).round(1)
      end

      private def human_size(bytes : Int64) : String
        return "#{bytes} B" if bytes < 1024
        return "#{(bytes / 1024.0).round(1)} KB" if bytes < 1024 * 1024
        return "#{(bytes / (1024.0 * 1024)).round(1)} MB" if bytes < 1024 * 1024 * 1024
        "#{(bytes / (1024.0 * 1024 * 1024)).round(1)} GB"
      end

      private def parse_env_size(var_name : String) : Int64?
        value = ENV[var_name]?
        return nil unless value

        value.to_i64?
      end
    end
  end
end
