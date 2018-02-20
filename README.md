# Baked File System

[![Build Status](https://travis-ci.org/schovi/baked_file_system.svg?branch=master)](https://travis-ci.org/schovi/baked_file_system)

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

Better and more often usage will be, when you need to locate files in your repository
That repository can be in different locations (imagine more ppl working on same program)

```crystal
class FileStorage
  BakedFileSystem.load("../public")
end

```

And finally how to get files from that storage

```crystal
file = FileStorage.get("path/to/file.png")

file.gets    # returns content of file
file.path    # returns path of file
file.mime_type    # returns mime type
file.size    # returns size of original file
```

When try to get missing file, `BakedFileSystem.get` raises a `BakedFileSystem::NoSuchFileError` exception
while `BakedFileSystem.get?` returns `nil`.

```crystal
begin
  FileStorage.get "missing/file"
rescue BakedFileSystem::NoSuchFileError
  puts "File #{path} is missing"
end

FileStorage.get? "missing/file" # => nil
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
