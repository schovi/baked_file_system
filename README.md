# Baked File System

Include (bake them) static files into your binary and access them anytime you need.

## Installation


Add this to your application's `shard.yml`:

```yaml
dependencies:
  baked_file_system:
    github: schovi/baked_file_system
```


## Usage

Load library with:

```crystal
require "baked_file_system"

```

Load folder with absolute path

```crystal
class FileStorage
  BakedFileSystem.load("/home/my_name/work/crystal_project/public")
end
```

Better and more often usage will be this, where you need to locate files in your repository
That repository can be in different locations (imagine more ppl working on same program)
Use relative path and pass second argument `__DIR__`

This weird API is because how crystal macros and variable/constants resolving in them works. You cant pass any expression in them

```crystal
class FileStorage
  BakedFileSystem.load("../public", __DIR__)
end

```

And finally how to get files from that storage

```crystal
file = FileStorage.get("path/to/file.png")

file.read    # returns content of file
file.encoded # returns encoded content, which can be used in base64 urls
file.name    # returns name of file
file.mime    # returns mime type
file.size    # returns size of original file
```

When try to get missing file, BakedFileSystem thows BakedFileSystem::NoSuchFileError exception

```crystal
path = "missing/file"

begin
  FileStorage.get(path)
rescue BakedFileSystem::NoSuchFileError
  puts "File #{path} is missing"
end
```

## Development

TODO: Write development instructions here

## Contributing

1. Fork it ( https://github.com/schovi/baked_file_system/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [schovi](https://github.com/schovi) David Schovanec - creator, maintainer
