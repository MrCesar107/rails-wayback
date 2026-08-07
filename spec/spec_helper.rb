# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "fileutils"
require "pathname"
require "tmpdir"
require "open3"

# rails_wayback.rb only requires the engine when Rails is loaded, so
# these specs can boot without Rails and still exercise the plain
# library components.
require "rails_wayback"

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before do
    RailsWayback.reset_configuration!
  end
end

module SpecSupport
  module_function

  def with_tmp_root
    Dir.mktmpdir("rails-wayback-spec-") do |dir|
      pathname = Pathname.new(dir)
      RailsWayback.configure do |c|
        c.app_root = pathname
        c.cache_root = pathname.join("tmp", "rails_wayback")
      end
      yield pathname
    end
  end

  def build_git_repo(root)
    Dir.chdir(root) do
      run("git", "init", "--quiet", "--initial-branch=main")
      run("git", "config", "user.email", "test@example.com")
      run("git", "config", "user.name", "Test")
      run("git", "config", "commit.gpgsign", "false")
    end
  end

  def commit_file(root, path, content, message:)
    Dir.chdir(root) do
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
      run("git", "add", path)
      run("git", "commit", "--quiet", "-m", message)
    end
  end

  def run(*cmd)
    out, err, status = Open3.capture3(*cmd)
    raise "cmd failed: #{cmd.inspect}\n#{err}" unless status.success?

    out
  end
end
