require "./loader/*"

path = ARGV[0]

if ARGV[1]?
  path = File.expand_path(File.join(ARGV[1], path))
end

puts BakedFileSystem::Loader.load_paths(path)
