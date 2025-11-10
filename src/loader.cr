require "./loader/*"
require "json"

path = File.expand_path(ARGV[0], ARGV[1])
include_dotfiles = ARGV[2]? == "true"

# Parse filter patterns from JSON (ARGV[3])
include_patterns : Array(String)? = nil
exclude_patterns : Array(String)? = nil

if ARGV[3]? && ARGV[3] != "nil"
  begin
    filter_data = JSON.parse(ARGV[3])
    # Check if include key exists and is not null
    if filter_data["include"]? && filter_data["include"].raw != nil
      include_patterns = filter_data["include"].as_a.map(&.as_s)
    end
    # Check if exclude key exists and is not null
    if filter_data["exclude"]? && filter_data["exclude"].raw != nil
      exclude_patterns = filter_data["exclude"].as_a.map(&.as_s)
    end
  rescue ex : JSON::ParseException
    # If JSON parsing fails, treat as no filters
    STDERR.puts "Warning: Failed to parse filter patterns: #{ex.message}"
  end
end

max_size = ARGV[4]? && ARGV[4] != "nil" ? ARGV[4].to_i64 : nil

BakedFileSystem::Loader.load(STDOUT, path, include_dotfiles, include_patterns, exclude_patterns, max_size)
