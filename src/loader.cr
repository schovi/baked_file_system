require "./loader/*"

path = File.expand_path(ARGV[0], ARGV[1])
include_dotfiles = ARGV[2]? == "true"

BakedFileSystem::Loader.load(STDOUT, path, include_dotfiles)
