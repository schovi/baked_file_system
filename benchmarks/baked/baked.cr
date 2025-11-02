require "kemal"
require "baked_file_system"

module Assets
  extend BakedFileSystem
  bake_folder "../public"
end

get "/files/:name" do |env|
  if file = Assets.get?(env.params.url["name"])
    file.gets_to_end
  else
    env.response.status_code = 404
    "Not found"
  end
end

Kemal.run(3001)
