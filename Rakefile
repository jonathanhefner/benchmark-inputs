require "bundler/gem_tasks"
require "rake/testtask"
require "yard"


desc 'Launch IRB with this gem pre-loaded'
task :irb do
  require "benchmark/inputs"
  require "irb"
  ARGV.clear
  IRB.start
end

YARD::Rake::YardocTask.new(:doc) do |t|
end

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList['test/**/*_test.rb']
end

task :default => :test
