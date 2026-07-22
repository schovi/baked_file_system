require "./loader/*"

private def parse_patterns(payload : String) : Array(String)?
  return nil if payload == "nil"

  patterns = [] of String
  offset = 0
  while offset < payload.size
    separator = payload.index(':', offset)
    raise ArgumentError.new("Invalid filter patterns") unless separator

    pattern_size = payload[offset, separator - offset].to_i?
    raise ArgumentError.new("Invalid filter patterns") unless pattern_size && pattern_size >= 0

    pattern_start = separator + 1
    pattern_end = pattern_start + pattern_size
    raise ArgumentError.new("Invalid filter patterns") if pattern_end > payload.size

    escaped_pattern = payload[pattern_start, pattern_size]
    patterns << escaped_pattern.gsub(/\\([\\0])/) { $1 == "0" ? "\0" : "\\" }
    offset = pattern_end
  end

  patterns
end

path = File.expand_path(ARGV[0], ARGV[1])
include_dotfiles = ARGV[2]? == "true"

include_payload = ARGV[3]? || raise ArgumentError.new("Missing filter patterns")
exclude_payload = ARGV[4]? || raise ArgumentError.new("Missing filter patterns")
include_patterns = parse_patterns(include_payload)
exclude_patterns = parse_patterns(exclude_payload)

max_size = ARGV[5]? && ARGV[5] != "nil" ? ARGV[5].to_i64 : nil
compress = ARGV[6]? != "false"

BakedFileSystem::Loader.load(STDOUT, path, include_dotfiles, include_patterns, exclude_patterns, max_size, compress)
