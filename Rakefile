# Look in the tasks/setup.rb file for the various options that can be
# configured in this Rakefile. The .rake files in the tasks directory
# are where the options are used.

begin
  require 'bones'
  Bones.setup
rescue LoadError
  begin
    load 'tasks/setup.rb'
  rescue LoadError
    raise RuntimeError, '### please install the "bones" gem ###'
  end
end

ensure_in_path 'lib'
require 'grackle'

task :default => 'spec:run'

PROJ.name = 'grackle'
PROJ.authors = 'Hayes Davis'
PROJ.email = 'hayes@appozite.com'
PROJ.url = 'http://github.com/hayesdavis/grackle'
PROJ.version = Grackle::VERSION
PROJ.rubyforge.name = 'grackle'

PROJ.spec.opts << '--color'

# EOF
