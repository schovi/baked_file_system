require "spec"
require "../src/baked_fs"

STORAGE_PATH = "./storage"

class Storage
  BakedFs.load(STORAGE_PATH, __DIR__)
end
