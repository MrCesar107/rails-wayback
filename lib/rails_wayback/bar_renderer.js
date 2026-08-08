(function (root, factory) {
  const Toolbar = factory();

  if (typeof module !== "undefined" && module.exports) module.exports = Toolbar;
  if (root) root.RailsWaybackToolbar = Toolbar;

  if (root && root.document) {
    const bar = root.document.getElementById("rails-wayback-bar");
    if (bar && !bar.railsWaybackToolbar) {
      bar.railsWaybackToolbar = new Toolbar(bar);
      bar.railsWaybackToolbar.connect();
    }
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  class RailsWaybackToolbar {
    constructor(element, dependencies) {
      const options = dependencies || {};
      const runtimeWindow = options.window || window;

      this.element = element;
      this.window = runtimeWindow;
      this.document = options.document || runtimeWindow.document;
      this.fetch = options.fetch || runtimeWindow.fetch.bind(runtimeWindow);
      this.search = options.search || runtimeWindow.RailsWaybackSearch;
      this.AbortController = options.AbortController || runtimeWindow.AbortController;

      this.handleBranchSearch = this.handleBranchSearch.bind(this);
      this.handleCommitSearch = this.handleCommitSearch.bind(this);
      this.handleBranchChange = this.handleBranchChange.bind(this);
      this.handleCommitChange = this.handleCommitChange.bind(this);
      this.travel = this.travel.bind(this);
      this.reset = this.reset.bind(this);
    }

    connect() {
      if (this.lifecycleController && !this.lifecycleController.signal.aborted) {
        return this.initialLoad;
      }

      this.readState();
      this.findElements();
      this.lifecycleController = new this.AbortController();
      this.bindEvents(this.lifecycleController.signal);
      this.setState();
      this.initialLoad = this.fetchBranches();
      return this.initialLoad;
    }

    disconnect() {
      if (this.lifecycleController) this.lifecycleController.abort();
      if (this.branchRequest) this.branchRequest.abort();
      if (this.commitRequest) this.commitRequest.abort();
    }

    readState() {
      this.mount = this.element.dataset.mount;
      this.headBranch = this.element.dataset.branch;
      this.headCommit = this.element.dataset.commit;
      this.activeRef = this.element.dataset.activeRef || "";
      this.activeBranch = this.element.dataset.activeBranch || "";
      this.refError = this.element.dataset.refError || "";
      this.references = [];
      this.commits = [];
      this.selectedBranchValue = this.activeBranch || this.headBranch;
      this.selectedCommitValue = this.activeRef || this.headCommit;
    }

    findElements() {
      this.branchSel = this.element.querySelector("[data-rw-branch]");
      this.commitSel = this.element.querySelector("[data-rw-commit]");
      this.branchSearch = this.element.querySelector("[data-rw-branch-search]");
      this.commitSearch = this.element.querySelector("[data-rw-commit-search]");
      this.branchResults = this.element.querySelector("[data-rw-branch-results]");
      this.commitResults = this.element.querySelector("[data-rw-commit-results]");
      this.stateEl = this.element.querySelector("[data-rw-state]");
      this.travelBtn = this.element.querySelector("[data-rw-travel]");
      this.resetBtn = this.element.querySelector("[data-rw-reset]");
    }

    bindEvents(signal) {
      const options = { signal: signal };
      this.branchSearch.addEventListener("input", this.handleBranchSearch, options);
      this.commitSearch.addEventListener("input", this.handleCommitSearch, options);
      this.branchSel.addEventListener("change", this.handleBranchChange, options);
      this.commitSel.addEventListener("change", this.handleCommitChange, options);
      this.travelBtn.addEventListener("click", this.travel, options);
      this.resetBtn.addEventListener("click", this.reset, options);
    }

    handleBranchSearch(event) {
      this.renderReferences(event.target.value);
    }

    handleCommitSearch(event) {
      this.renderCommits(event.target.value);
    }

    handleBranchChange(event) {
      this.selectedBranchValue = event.target.value;
      this.selectedCommitValue = "";
      this.branchSearch.value = "";
      this.commitSearch.value = "";
      this.renderReferences("");
      this.fetchCommits(this.selectedBranchValue);
    }

    handleCommitChange(event) {
      this.selectedCommitValue = event.target.value;
    }

    setState() {
      if (this.refError) {
        this.stateEl.textContent = "Travel rejected";
        this.stateEl.classList.add("rw-active");
        this.resetBtn.hidden = false;
      } else if (this.activeRef) {
        const label = this.activeBranch
          ? this.referenceLabel(this.activeBranch) + "@" + this.activeRef.slice(0, 7)
          : this.activeRef.slice(0, 7);
        this.stateEl.textContent = "Traveling: " + label;
        this.stateEl.classList.add("rw-active");
        this.resetBtn.hidden = false;
      } else {
        this.stateEl.textContent = "Live";
        this.stateEl.classList.remove("rw-active");
        this.resetBtn.hidden = true;
      }
    }

    showError(message) {
      this.stateEl.textContent = message;
      this.stateEl.classList.add("rw-active");
    }

    referenceLabel(reference) {
      if (reference.indexOf("refs/heads/") === 0) return reference.slice(11);
      if (reference.indexOf("refs/remotes/") === 0) return reference.slice(13);
      if (reference.indexOf("refs/tags/") === 0) return "tag:" + reference.slice(10);
      return reference;
    }

    referenceMatchesSelection(reference, selection) {
      return reference.full_name === selection ||
        reference.name === selection ||
        reference.label === selection;
    }

    resultMessage(count, noun, query, selectionRetained) {
      if (!query.trim()) return count + " " + noun + (count === 1 ? "" : "s") + " loaded";
      if (count > 0) return count + " matching " + noun + (count === 1 ? "" : "s");
      return "No matching " + noun + "s" +
        (selectionRetained ? "; current selection retained" : "");
    }

    renderReferences(query) {
      const result = this.search.searchReferences(
        this.references,
        query,
        this.selectedBranchValue
      );
      this.branchSel.innerHTML = "";
      result.visible.forEach((reference) => {
        const option = this.document.createElement("option");
        option.value = reference.full_name;
        option.textContent = reference.label;
        option.selected = reference.full_name === this.selectedBranchValue;
        this.branchSel.appendChild(option);
      });

      if (!this.branchSel.value && result.visible.length > 0) {
        this.selectedBranchValue = result.visible[0].full_name;
        this.branchSel.value = this.selectedBranchValue;
      }
      const retained = result.visible.length > result.matches.length;
      this.branchResults.textContent = this.resultMessage(
        result.matches.length,
        "ref",
        query,
        retained
      );
      this.branchSearch.setAttribute(
        "aria-invalid",
        result.matches.length === 0 && query.trim() ? "true" : "false"
      );
    }

    renderCommits(query) {
      const result = this.search.searchCommits(this.commits, query, this.selectedCommitValue);
      this.commitSel.innerHTML = "";
      result.visible.forEach((commit) => {
        const option = this.document.createElement("option");
        option.value = commit.sha;
        option.textContent = commit.short_sha + " — " + (commit.subject || "").slice(0, 80);
        option.selected = commit.sha === this.selectedCommitValue;
        this.commitSel.appendChild(option);
      });

      if (!this.commitSel.value && result.visible.length > 0) {
        this.selectedCommitValue = result.visible[0].sha;
        this.commitSel.value = this.selectedCommitValue;
      }
      const retained = result.visible.length > result.matches.length;
      this.commitResults.textContent = this.resultMessage(
        result.matches.length,
        "commit",
        query,
        retained
      );
      this.commitSearch.setAttribute(
        "aria-invalid",
        result.matches.length === 0 && query.trim() ? "true" : "false"
      );
      this.travelBtn.disabled = !this.commitSel.value;
    }

    async fetchBranches() {
      const request = this.startRequest("branchRequest");
      this.branchSearch.disabled = true;
      this.branchSel.disabled = true;
      this.branchResults.textContent = "Loading refs";

      try {
        const response = await this.fetch(this.mount + "/branches", {
          headers: { Accept: "application/json" },
          signal: request.signal
        });
        if (!response.ok) throw new Error("HTTP " + response.status + " on /branches");

        const data = await response.json();
        if (!this.requestIsCurrent("branchRequest", request)) return;

        this.references = data.refs || (data.branches || []).map((branch) => ({
          full_name: branch,
          name: branch,
          label: branch,
          type: "branch"
        }));
        const initial = this.references.find((reference) => (
          this.referenceMatchesSelection(reference, this.selectedBranchValue)
        ));
        this.selectedBranchValue = initial
          ? initial.full_name
          : this.references[0] && this.references[0].full_name;
        this.renderReferences(this.branchSearch.value);
        this.branchSearch.disabled = this.references.length === 0;
        this.branchSel.disabled = this.references.length === 0;
        if ((data.errors || []).length > 0) this.showError(data.errors.join(" | "));
        if (this.branchSel.value) await this.fetchCommits(this.branchSel.value);
      } catch (error) {
        if (this.requestWasCancelled("branchRequest", request, error)) return;

        this.branchResults.textContent = "Refs unavailable";
        this.showError("branches: " + error.message);
      }
    }

    async fetchCommits(branch) {
      const request = this.startRequest("commitRequest");
      this.travelBtn.disabled = true;
      this.commitSearch.disabled = true;
      this.commitSel.disabled = true;
      this.commitResults.textContent = "Loading commits";

      try {
        const response = await this.fetch(this.mount + "/commits/" + encodeURI(branch), {
          headers: { Accept: "application/json" },
          signal: request.signal
        });
        if (!response.ok) {
          throw new Error("HTTP " + response.status + " on /commits/" + branch);
        }

        const data = await response.json();
        if (!this.requestIsCurrent("commitRequest", request)) return;

        this.commits = data.commits || [];
        if (!this.commits.some((commit) => commit.sha === this.selectedCommitValue)) {
          this.selectedCommitValue = this.commits[0] && this.commits[0].sha;
        }
        this.renderCommits(this.commitSearch.value);
        this.commitSearch.disabled = this.commits.length === 0;
        this.commitSel.disabled = this.commits.length === 0;
        if (data.error) {
          this.showError("commits: " + data.error);
        } else if (!this.activeRef) {
          this.setState();
        }
      } catch (error) {
        if (this.requestWasCancelled("commitRequest", request, error)) return;

        this.commitResults.textContent = "Commits unavailable";
        this.showError("commits: " + error.message);
      }
    }

    startRequest(property) {
      if (this[property]) this[property].abort();
      const request = new this.AbortController();
      this[property] = request;
      return request;
    }

    requestIsCurrent(property, request) {
      return this[property] === request && !request.signal.aborted;
    }

    requestWasCancelled(property, request, error) {
      return error.name === "AbortError" || !this.requestIsCurrent(property, request);
    }

    setCookie(name, value) {
      this.document.cookie = name + "=" + encodeURIComponent(value) + "; Path=/; SameSite=Lax";
    }

    travel() {
      const sha = this.commitSel.value;
      if (!sha || !this.trustWarningAccepted()) return;

      this.setCookie("rails_wayback_ref", sha);
      if (this.branchSel.value) this.setCookie("rails_wayback_branch", this.branchSel.value);
      const url = new this.window.URL(this.window.location.href);
      url.searchParams.set("_wayback_ref", sha);
      if (this.branchSel.value) url.searchParams.set("_wayback_branch", this.branchSel.value);
      this.window.location.assign(url.toString());
    }

    trustWarningAccepted() {
      const key = "rails-wayback.trust-warning-accepted";
      try {
        if (this.window.sessionStorage.getItem(key) === "true") return true;
      } catch (_error) {
        // Storage may be unavailable; confirmation still protects this action.
      }

      const accepted = this.window.confirm(
        "Historical templates execute Ruby inside this Rails process. " +
        "Continue only if you trust this commit."
      );
      if (accepted) {
        try {
          this.window.sessionStorage.setItem(key, "true");
        } catch (_error) {
          // The confirmation remains effective for this travel action.
        }
      }
      return accepted;
    }

    reset() {
      const url = new this.window.URL(this.window.location.href);
      url.searchParams.delete("_wayback_ref");
      url.searchParams.delete("_wayback_branch");

      const resetUrl = new this.window.URL(this.mount + "/reset", this.window.location.origin);
      resetUrl.searchParams.set("return_to", url.pathname + url.search + url.hash);
      this.window.location.assign(resetUrl.toString());
    }
  }

  return RailsWaybackToolbar;
});
