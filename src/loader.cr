require "./loader/*"

path   = ARGV[0]
source = ARGV[1]

unless source.empty?
  path = File.expand_path(File.join(source, path))
end

root = BakedFs::Loader.load(path)
puts root.to_json
