require "kemal"

get "/files/:name" do |env|
  filepath = File.join("../public", env.params.url["name"])
  File.exists?(filepath) ? send_file(env, filepath) : (env.response.status_code = 404; "Not found")
end

Kemal.run(3000)
