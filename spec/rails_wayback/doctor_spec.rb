# frozen_string_literal: true

RSpec.describe RailsWayback::Doctor do
  it "reports a ready host with external tools, a repository, and writable cache" do
    SpecSupport.with_tmp_root do |root|
      SpecSupport.build_git_repo(root)
      SpecSupport.commit_file(root, "app/views/home/index.html.erb", "<h1>Home</h1>", message: "home")

      result = described_class.new(environment: "test").call

      expect(result).to be_ready
      expect(result.exit_status).to eq(0)
      expect(result.checks.map(&:name)).to include(
        "Rails environment",
        "Application root",
        "Git",
        "Git repository",
        "tar",
        "Cache directory",
        "Configured paths"
      )
      expect(result.checks).not_to include(have_attributes(status: :error))
    end
  end

  it "returns errors when required executables are missing" do
    missing = lambda do |command, *|
      raise Errno::ENOENT, command
    end
    git = instance_spy(RailsWayback::Git)

    SpecSupport.with_tmp_root do
      result = described_class.new(git: git, environment: "test", capture3: missing).call

      expect(result).not_to be_ready
      expect(result.exit_status).to eq(1)
      expect(result.checks).to include(
        have_attributes(name: "Git", status: :error, message: include("not found in PATH")),
        have_attributes(name: "tar", status: :error, message: include("not found in PATH"))
      )
      expect(git).not_to have_received(:repository?)
    end
  end

  it "warns without failing when no configured paths exist in the current tree" do
    status = instance_double(Process::Status, success?: true)
    capture3 = ->(command, *) { ["#{command} version", "", status] }
    git = instance_double(RailsWayback::Git, repository?: true, root: Pathname.new("/tmp"))

    SpecSupport.with_tmp_root do
      result = described_class.new(git: git, environment: "test", capture3: capture3).call
      paths = result.checks.find { |check| check.name == "Configured paths" }

      expect(result).to be_ready
      expect(paths.status).to eq(:warning)
      expect(paths.message).to start_with("0/4 exist")
    end
  end

  it "fails for a disallowed environment and unsafe configured paths" do
    status = instance_double(Process::Status, success?: true)
    capture3 = ->(command, *) { ["#{command} version", "", status] }
    git = instance_double(RailsWayback::Git, repository?: true, root: Pathname.new("/tmp"))

    SpecSupport.with_tmp_root do
      RailsWayback.configuration.view_paths = ["../secrets"]
      result = described_class.new(git: git, environment: "production", capture3: capture3).call

      expect(result).not_to be_ready
      expect(result.checks).to include(
        have_attributes(name: "Rails environment", status: :error),
        have_attributes(name: "Configured paths", status: :error)
      )
    end
  end
end
