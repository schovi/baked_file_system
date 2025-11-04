require "./loader/*"

path = File.expand_path(ARGV[0], ARGV[1])
include_dotfiles = ARGV[2]? == "true"
max_size = ARGV[3]? && ARGV[3] != "nil" ? ARGV[3].to_i64 : nil

BakedFileSystem::Loader.load(STDOUT, path, include_dotfiles, max_size)
