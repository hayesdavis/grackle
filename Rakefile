task :test do
  test_root = File.expand_path(File.dirname(__FILE__)+"/test")
  require File.join(test_root,"test_helper")
  Dir.glob("#{test_root}/**/*_test.rb") do |file|
    require File.expand_path(file)
  end
end