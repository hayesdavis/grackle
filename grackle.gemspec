$LOAD_PATH.unshift './lib'
require 'grackle/version'

Gem::Specification.new do |s|
  s.name        = "grackle"
  s.version     = Grackle::VERSION
  s.summary     = "Grackle is a lightweight library for the Twitter REST and Search API."
  s.homepage    = "http://github.com/hayesdavis/grackle"

  s.authors     = ["Hayes Davis"]
  s.email       = "hayes@unionmetrics.com"

  s.files       += %w(README.rdoc CHANGELOG.rdoc)
  s.files       += Dir.glob("lib/**/*")
  s.files       += Dir.glob("test/**/*")

  s.extra_rdoc_files  = %w(README.rdoc CHANGELOG.rdoc)

  s.description = <<-description
    Grackle is a library for the Twitter REST and Search API designed to not
    require a new release in the face Twitter API changes or errors.
  description

  s.add_dependency "json"
  s.add_dependency "mime-types"
  s.add_dependency "oauth"
end