require "../src/baked_file_system"

# This example demonstrates BakedFileSystem's automatic size warnings
#
# To see warnings with these small test files, set environment variables:
#   BAKED_FILE_SYSTEM_WARN_THRESHOLD=30000    # 30KB - warns about total size
#   BAKED_FILE_SYSTEM_MAX_SIZE=200000         # 200KB - allows compilation
#
# Run with:
#   BAKED_FILE_SYSTEM_WARN_THRESHOLD=30000 crystal build warning_example.cr
#
# When you compile this example, you'll see:
# 1. A report showing total embedded files and compression ratio
# 2. Warnings for large individual files (>1MB compressed by default, or lower with env var)
# 3. A warning about significant total size (>30KB with env var above)
#
# Note: These are just warnings - compilation will still succeed!

module Assets
  extend BakedFileSystem

  # Embed all files from the assets directory
  # - small.txt: 10KB → ~55 bytes (highly compressible zeros)
  # - medium.bin: 50KB → ~50KB (random data, doesn't compress)
  # - large.bin: 100KB → ~100KB (random data, doesn't compress)
  # Total: ~150KB compressed
  bake_folder "./assets"
end

# Display what was embedded
puts "Successfully embedded #{Assets.files.size} files!"
puts "\nEmbedded files:"
Assets.files.each do |file|
  size_kb = (file.size / 1024.0).round(2)
  puts "  #{file.path}: #{size_kb} KB"
end

# Show that files are accessible
puts "\nAccessing a file:"
small_file = Assets.get("/small.txt")
puts "  Path: #{small_file.path}"
puts "  Size: #{small_file.size} bytes"

# Read first 50 bytes
buffer = Bytes.new(50)
small_file.read(buffer)
puts "  First 50 bytes (hex): #{buffer.hexstring}"
