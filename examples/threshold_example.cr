require "../src/baked_file_system"

# This example demonstrates BakedFileSystem's max_size enforcement
#
# When you try to compile this example, it will FAIL with an error like:
#
#   ❌  ERROR: Total embedded size (153.7 KB) exceeds limit (50.0 KB)
#       Reduce the number/size of embedded files or increase the limit.
#
# This prevents accidentally creating huge binaries!

module Assets
  extend BakedFileSystem

  # Try to embed all files with a very strict size limit (50KB)
  # The assets directory contains ~150KB of compressed data, so this will fail!
  # - small.txt: 10KB → ~55 bytes compressed
  # - medium.bin: 50KB → ~50KB compressed
  # - large.bin: 100KB → ~100KB compressed
  # Total: ~150KB compressed
  bake_folder path: "./assets", max_size: 51_200 # 50 KB limit - will fail!
end

# This code will never execute because compilation fails above
puts "Successfully embedded #{Assets.files.size} files!"
