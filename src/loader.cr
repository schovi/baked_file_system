require "./loader/*"

path = File.expand_path(ARGV[0], ARGV[1])

BakedFileSystem::Loader.load(STDOUT, path)
