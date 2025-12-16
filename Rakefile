require 'rspec/core/rake_task'

# Load the project environment
task default: [:spec]

# Run unit tests
desc "Run unit tests"
task :spec do
  RSpec::Core::RakeTask.new(:spec) do |t|
    t.pattern = 'spec/**/*_spec.rb'
  end
end

# Run acceptance tests
desc "Run acceptance tests"
task :acceptance do
  sh "ruby acceptance_test.rb"
end

# Run demo
desc "Run demo"
task :demo do
  sh "ruby demo.rb"
end

# Run all tests
desc "Run all tests"
task :test => [:spec, :acceptance] do
  puts "All tests completed!"
end

# Clean up test files
desc "Clean up test files"
task :clean do
  Dir['*.json'].each { |f| File.delete(f) if f != '.env.test' }
  Dir['tmp_*.json'].each { |f| File.delete(f) if File.exist?(f) }
  Dir['tmp_*.ics'].each { |f| File.delete(f) if File.exist?(f) }
  puts "Test files cleaned up"
end