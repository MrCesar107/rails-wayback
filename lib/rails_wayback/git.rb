# frozen_string_literal: true

require "open3"
require "pathname"

module RailsWayback
  # Thin wrapper around shell git for the host application repository.
  #
  # We shell out to git instead of pulling in a dependency to keep the
  # gem light. All commands are scoped to the host app root and return
  # plain Ruby data structures.
  #
  # NOTE: Maybe we should need to use a git library instead of shelling out to git.
  # Only if this functionality is not enough for the gem on the future.
  class Git
    Commit = Struct.new(:sha, :short_sha, :subject, :author, :date, keyword_init: true)
    Reference = Struct.new(:full_name, :name, :kind, :label, keyword_init: true)
    REFERENCE_PREFIXES = {
      "refs/heads/" => :branch,
      "refs/remotes/" => :remote,
      "refs/tags/" => :tag
    }.freeze
    REFERENCE_KIND_ORDER = { branch: 0, remote: 1, tag: 2 }.freeze

    class GitError < StandardError; end
    class ExecutableNotFoundError < GitError; end

    def initialize(root: nil)
      @root = Pathname.new(root || RailsWayback.configuration.app_root_path)
    end

    def repository?
      run("rev-parse", "--is-inside-work-tree").strip == "true"
    rescue GitError
      false
    end

    def current_branch
      run("rev-parse", "--abbrev-ref", "HEAD").strip
    end

    def current_commit
      run("rev-parse", "HEAD").strip
    end

    def branches
      output = run("for-each-ref", "--format=%(refname:short)", "refs/heads/")
      output.split("\n").map(&:strip).reject(&:empty?)
    end

    # Lists refs that are already present in the local repository and match
    # the same trust patterns used to authorize historical rendering. This
    # never fetches or mutates Git state.
    def references(patterns: RailsWayback.configuration.trusted_ref_patterns)
      output = run(
        "for-each-ref",
        "--format=%(refname)%09%(symref)",
        "refs/heads/",
        "refs/remotes/",
        "refs/tags/"
      )

      discovered = output.split("\n").filter_map do |line|
        full_name, symbolic_target = line.split("\t", 2)
        next unless symbolic_target.to_s.empty?
        next unless trusted_reference?(full_name, patterns)

        build_reference(full_name)
      end
      discovered.sort_by { |reference| [REFERENCE_KIND_ORDER.fetch(reference.kind), reference.label] }
    end

    # Resolves either a canonical full ref name (preferred) or a legacy short
    # branch name, but only from the configured trusted discovery set.
    def reference(selector, patterns: RailsWayback.configuration.trusted_ref_patterns)
      available = references(patterns: patterns)
      input = selector.to_s
      exact = available.find { |candidate| candidate.full_name == input }
      return exact if exact

      compatible = available.find do |candidate|
        candidate.name == input || candidate.label == input
      end
      return compatible if compatible

      raise GitError, "Git ref #{input.inspect} is not trusted or is unavailable locally"
    end

    def commits(branch, limit: RailsWayback.configuration.max_commits)
      output = run(
        "log",
        branch,
        "--max-count=#{limit.to_i}",
        "--pretty=format:%H%x1f%h%x1f%s%x1f%an%x1f%ad",
        "--date=iso-strict"
      )
      output.split("\n").reject(&:empty?).map do |line|
        sha, short, subject, author, date = line.split("\x1f", 5)
        Commit.new(sha: sha, short_sha: short, subject: subject, author: author, date: date)
      end
    end

    def resolve_ref(ref)
      run("rev-parse", "--verify", "#{ref}^{commit}").strip
    rescue ExecutableNotFoundError
      raise
    rescue GitError
      raise RefNotFoundError, "Unknown git ref: #{ref.inspect}"
    end

    def show(ref, path)
      run("show", "#{ref}:#{path}")
    end

    def tree?(ref, path)
      run("cat-file", "-t", "#{ref}:#{path}").strip == "tree"
    rescue ExecutableNotFoundError
      raise
    rescue GitError
      false
    end

    # Returns the local branch names that contain `sha` in their history.
    # Used by the bar to reflect the branch you are RENDERING with when
    # you travel, instead of the branch that is checked out on disk
    # (which never moves — the gem never touches your working tree).
    def branches_containing(sha)
      output = run("branch", "--contains", sha, "--format=%(refname:short)")
      output.split("\n").map(&:strip).reject(&:empty?)
    rescue GitError
      []
    end

    def refs_containing(sha)
      output = run("for-each-ref", "--contains=#{sha}", "--format=%(refname)")
      output.split("\n").map(&:strip).reject(&:empty?)
    end

    # Same as `branches_containing`, but picks the most contextual one
    # for display in the bar when the developer did NOT provide an
    # explicit branch alongside the sha:
    # * if the current branch contains the sha, prefer it (keeps you in
    #   your own context — the sha is on your history line),
    # * otherwise pick the first non-current local branch that contains
    #   it (typical case of traveling AWAY from your branch),
    # * returns nil if no local branch contains the sha (detached ref).
    def resolve_branch_for(sha)
      candidates = branches_containing(sha)
      return nil if candidates.empty?

      here = current_branch
      return here if candidates.include?(here)

      candidates.first
    end

    # Returns the list of files that differ between `ref` and the current
    # working tree (unstaged changes included). Optionally scoped to a set
    # of pathspecs so we only report files inside the paths the gem
    # actually swaps for rendering. Never raises: on git failure we log
    # and return an empty list so a missing/broken ref never breaks the
    # bar.
    def diff_paths(ref, paths: [])
      args = ["diff", "--name-only", ref]
      args += ["--", *paths] unless paths.empty?
      output = run(*args)
      output.split("\n").map(&:strip).reject(&:empty?)
    rescue GitError => e
      if defined?(Rails) && Rails.respond_to?(:logger)
        Rails.logger.warn("[rails-wayback] diff_paths(#{ref.inspect}) failed: #{e.message}")
      end
      []
    end

    def checkout_ref(ref, into:)
      target = Pathname.new(into)
      FileUtils.mkdir_p(target)
      # `git --work-tree` + `checkout` writes the ref's contents into a
      # detached directory without touching the developer's HEAD or index.
      env = { "GIT_INDEX_FILE" => target.join(".rails_wayback_index").to_s }
      run_with_env(env, "--work-tree=#{target}", "read-tree", ref)
      run_with_env(env, "--work-tree=#{target}", "checkout-index", "--all", "--force")
      target
    ensure
      FileUtils.rm_f(target.join(".rails_wayback_index")) if target
    end

    attr_reader :root

    private

    def trusted_reference?(full_name, patterns)
      Array(patterns).map(&:to_s).any? { |pattern| File.fnmatch?(pattern, full_name) }
    end

    def build_reference(full_name)
      prefix, kind = REFERENCE_PREFIXES.find { |candidate, _value| full_name.start_with?(candidate) }
      return unless prefix

      name = full_name.delete_prefix(prefix)
      label = kind == :tag ? "tag:#{name}" : name
      Reference.new(full_name: full_name, name: name, kind: kind, label: label)
    end

    def run(*)
      run_with_env({}, *)
    end

    def run_with_env(env, *)
      stdout, stderr, status = Open3.capture3(env, "git", "-C", @root.to_s, *)
      raise GitError, stderr.strip unless status.success?

      stdout
    rescue Errno::ENOENT
      raise ExecutableNotFoundError,
            "Required executable `git` was not found in PATH. " \
            "Run `bundle exec rails-wayback doctor` for diagnostics."
    rescue SystemCallError => e
      raise GitError,
            "Could not execute required executable `git`: #{e.message}. " \
            "Run `bundle exec rails-wayback doctor` for diagnostics."
    end
  end
end
