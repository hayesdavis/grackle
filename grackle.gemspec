# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{grackle}
  s.version = "0.0.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Hayes Davis"]
  s.date = %q{2009-03-22}
  s.default_executable = %q{grackle}
  s.description = %q{Grackle is a library for the Twitter REST and Search API that aims to go with the flow.}
  s.email = %q{hayes@appozite.com}
  s.executables = ["grackle"]
  s.extra_rdoc_files = ["History.txt", "README.txt", "bin/grackle"]
  s.files = [".loadpath", ".project", "History.txt", "README.txt", "Rakefile", "bin/grackle", "grackle.gemspec", "lib/grackle.rb", "lib/grackle/client.rb", "lib/grackle/handlers.rb", "lib/grackle/transport.rb", "lib/grackle/utils.rb", "spec/grackle_spec.rb", "spec/spec_helper.rb", "test/test_grackle.rb"]
  s.has_rdoc = true
  s.homepage = %q{http://github.com/hayesdavis/grackle}
  s.rdoc_options = ["--main", "README.txt"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{grackle}
  s.rubygems_version = %q{1.3.1}
  s.summary = %q{Grackle is a library for the Twitter REST and Search API}
  s.test_files = ["test/test_grackle.rb"]

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 2

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<json>, [">= 0"])
      s.add_runtime_dependency(%q<httpclient>, [">= 2.1.4"])
      s.add_development_dependency(%q<bones>, [">= 2.4.2"])
    else
      s.add_dependency(%q<json>, [">= 0"])
      s.add_dependency(%q<httpclient>, [">= 2.1.4"])
      s.add_dependency(%q<bones>, [">= 2.4.2"])
    end
  else
    s.add_dependency(%q<json>, [">= 0"])
    s.add_dependency(%q<httpclient>, [">= 2.1.4"])
    s.add_dependency(%q<bones>, [">= 2.4.2"])
  end
end
