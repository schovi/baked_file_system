require "./loader/*"

path = File.expand_path(ARGV[0], ARGV[1])
puts BakedFileSystem::Loader.load(path)
