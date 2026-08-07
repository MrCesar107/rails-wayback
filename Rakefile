# frozen_string_literal: true

require "bundler/gem_tasks"

default_tasks = []

begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
  default_tasks << :spec
rescue LoadError
  # RSpec is only available in development
end

begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new(:rubocop) do |task|
    task.options = ["--parallel"]
  end
  desc "Run RuboCop"
  task lint: :rubocop
  default_tasks << :rubocop
rescue LoadError
  # RuboCop is only available in development
end

task default: default_tasks
