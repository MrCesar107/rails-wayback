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

      this.toggleBranchDropdown = this.toggleBranchDropdown.bind(this);
      this.toggleCommitDropdown = this.toggleCommitDropdown.bind(this);
      this.handleBranchSearch = this.handleBranchSearch.bind(this);
      this.handleCommitSearch = this.handleCommitSearch.bind(this);
      this.handleBranchOptionsClick = this.handleBranchOptionsClick.bind(this);
      this.handleCommitOptionsClick = this.handleCommitOptionsClick.bind(this);
      this.handleBranchKeydown = this.handleBranchKeydown.bind(this);
      this.handleCommitKeydown = this.handleCommitKeydown.bind(this);
      this.handleBranchTriggerKeydown = this.handleBranchTriggerKeydown.bind(this);
      this.handleCommitTriggerKeydown = this.handleCommitTriggerKeydown.bind(this);
      this.handleDocumentClick = this.handleDocumentClick.bind(this);
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
      this.activeBranchOption = -1;
      this.activeCommitOption = -1;
    }

    findElements() {
      this.branchCombobox = this.element.querySelector("[data-rw-branch-combobox]");
      this.branchTrigger = this.element.querySelector("[data-rw-branch-trigger]");
      this.branchValue = this.element.querySelector("[data-rw-branch-value]");
      this.branchDropdown = this.element.querySelector("[data-rw-branch-dropdown]");
      this.branchSearch = this.element.querySelector("[data-rw-branch-search]");
      this.branchOptions = this.element.querySelector("[data-rw-branch-options]");
      this.branchResults = this.element.querySelector("[data-rw-branch-results]");
      this.commitCombobox = this.element.querySelector("[data-rw-commit-combobox]");
      this.commitTrigger = this.element.querySelector("[data-rw-commit-trigger]");
      this.commitValue = this.element.querySelector("[data-rw-commit-value]");
      this.commitDropdown = this.element.querySelector("[data-rw-commit-dropdown]");
      this.commitSearch = this.element.querySelector("[data-rw-commit-search]");
      this.commitOptions = this.element.querySelector("[data-rw-commit-options]");
      this.commitResults = this.element.querySelector("[data-rw-commit-results]");
      this.stateEl = this.element.querySelector("[data-rw-state]");
      this.travelBtn = this.element.querySelector("[data-rw-travel]");
      this.resetBtn = this.element.querySelector("[data-rw-reset]");
    }

    bindEvents(signal) {
      const options = { signal: signal };
      this.branchTrigger.addEventListener("click", this.toggleBranchDropdown, options);
      this.commitTrigger.addEventListener("click", this.toggleCommitDropdown, options);
      this.branchTrigger.addEventListener("keydown", this.handleBranchTriggerKeydown, options);
      this.commitTrigger.addEventListener("keydown", this.handleCommitTriggerKeydown, options);
      this.branchSearch.addEventListener("input", this.handleBranchSearch, options);
      this.commitSearch.addEventListener("input", this.handleCommitSearch, options);
      this.branchSearch.addEventListener("keydown", this.handleBranchKeydown, options);
      this.commitSearch.addEventListener("keydown", this.handleCommitKeydown, options);
      this.branchOptions.addEventListener("click", this.handleBranchOptionsClick, options);
      this.commitOptions.addEventListener("click", this.handleCommitOptionsClick, options);
      this.document.addEventListener("click", this.handleDocumentClick, options);
      this.travelBtn.addEventListener("click", this.travel, options);
      this.resetBtn.addEventListener("click", this.reset, options);
    }

    controls(kind) {
      return {
        combobox: this[kind + "Combobox"],
        dropdown: this[kind + "Dropdown"],
        options: this[kind + "Options"],
        search: this[kind + "Search"],
        trigger: this[kind + "Trigger"]
      };
    }

    toggleBranchDropdown() {
      this.toggleDropdown("branch");
    }

    toggleCommitDropdown() {
      this.toggleDropdown("commit");
    }

    toggleDropdown(kind) {
      const control = this.controls(kind);
      if (control.trigger.disabled) return;
      if (control.dropdown.hidden) {
        this.openDropdown(kind);
      } else {
        this.closeDropdown(kind, true);
      }
    }

    openDropdown(kind) {
      const otherKind = kind === "branch" ? "commit" : "branch";
      const control = this.controls(kind);
      this.closeDropdown(otherKind, false);
      control.dropdown.hidden = false;
      control.trigger.setAttribute("aria-expanded", "true");
      control.search.setAttribute("aria-expanded", "true");
      control.search.focus();
    }

    closeDropdown(kind, restoreFocus) {
      const control = this.controls(kind);
      if (!control || !control.dropdown) return;
      control.dropdown.hidden = true;
      control.trigger.setAttribute("aria-expanded", "false");
      control.search.setAttribute("aria-expanded", "false");
      control.search.removeAttribute("aria-activedescendant");
      if (restoreFocus) control.trigger.focus();
    }

    handleDocumentClick(event) {
      if (this.element.contains(event.target)) return;
      this.closeDropdown("branch", false);
      this.closeDropdown("commit", false);
    }

    handleBranchSearch(event) {
      this.renderReferences(event.target.value);
    }

    handleCommitSearch(event) {
      this.renderCommits(event.target.value);
    }

    handleBranchTriggerKeydown(event) {
      this.handleTriggerKeydown("branch", event);
    }

    handleCommitTriggerKeydown(event) {
      this.handleTriggerKeydown("commit", event);
    }

    handleTriggerKeydown(kind, event) {
      if (["ArrowDown", "ArrowUp", "Enter", " "].indexOf(event.key) === -1) return;
      event.preventDefault();
      this.openDropdown(kind);
      if (event.key === "ArrowUp") this.moveActiveOption(kind, -1);
    }

    handleBranchKeydown(event) {
      this.handleSearchKeydown("branch", event);
    }

    handleCommitKeydown(event) {
      this.handleSearchKeydown("commit", event);
    }

    handleSearchKeydown(kind, event) {
      if (event.key === "Escape") {
        event.preventDefault();
        this.closeDropdown(kind, true);
      } else if (event.key === "ArrowDown") {
        event.preventDefault();
        this.moveActiveOption(kind, 1);
      } else if (event.key === "ArrowUp") {
        event.preventDefault();
        this.moveActiveOption(kind, -1);
      } else if (event.key === "Enter") {
        const control = this.controls(kind);
        const index = this[kind === "branch" ? "activeBranchOption" : "activeCommitOption"];
        const option = control.options.children[index];
        if (!option) return;
        event.preventDefault();
        this.selectOption(kind, option.dataset.rwOptionValue);
      }
    }

    moveActiveOption(kind, amount) {
      const control = this.controls(kind);
      const count = control.options.children.length;
      if (count === 0) return;
      const property = kind === "branch" ? "activeBranchOption" : "activeCommitOption";
      const current = this[property];
      const next = current < 0 ? (amount > 0 ? 0 : count - 1) : (current + amount + count) % count;
      this.setActiveOption(kind, next);
    }

    setActiveOption(kind, index) {
      const control = this.controls(kind);
      const property = kind === "branch" ? "activeBranchOption" : "activeCommitOption";
      this[property] = index;
      Array.from(control.options.children).forEach(function (option, optionIndex) {
        if (optionIndex === index) {
          option.classList.add("rw-active-option");
        } else {
          option.classList.remove("rw-active-option");
        }
      });
      const active = control.options.children[index];
      if (active) {
        control.search.setAttribute("aria-activedescendant", active.id);
        if (typeof active.scrollIntoView === "function") {
          active.scrollIntoView({ block: "nearest" });
        }
      } else {
        control.search.removeAttribute("aria-activedescendant");
      }
    }

    optionFromEvent(event, container) {
      let target = event.target;
      while (target && target !== container) {
        if (target.dataset && target.dataset.rwOptionValue) return target;
        target = target.parentNode;
      }
      return null;
    }

    handleBranchOptionsClick(event) {
      const option = this.optionFromEvent(event, this.branchOptions);
      if (option) this.selectOption("branch", option.dataset.rwOptionValue);
    }

    handleCommitOptionsClick(event) {
      const option = this.optionFromEvent(event, this.commitOptions);
      if (option) this.selectOption("commit", option.dataset.rwOptionValue);
    }

    selectOption(kind, value) {
      if (kind === "branch") {
        const changed = value !== this.selectedBranchValue;
        this.selectedBranchValue = value;
        this.branchSearch.value = "";
        this.renderReferences("");
        this.closeDropdown("branch", true);
        if (changed) {
          this.selectedCommitValue = "";
          this.commits = [];
          this.commitSearch.value = "";
          this.commitOptions.innerHTML = "";
          this.commitDropdown.hidden = true;
          this.commitTrigger.disabled = true;
          this.commitValue.textContent = "Loading commits…";
          this.commitResults.textContent = "Loading commits";
          this.travelBtn.disabled = true;
          this.fetchCommits(value);
        }
      } else {
        this.selectedCommitValue = value;
        this.commitSearch.value = "";
        this.renderCommits("");
        this.closeDropdown("commit", true);
      }
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

    buildOption(kind, value, label, selected, index) {
      const option = this.document.createElement("button");
      option.type = "button";
      option.className = "rw-combobox-option";
      option.id = "rails-wayback-" + kind + "-option-" + index;
      option.dataset.rwOptionValue = value;
      option.textContent = label;
      option.tabIndex = -1;
      option.setAttribute("role", "option");
      option.setAttribute("aria-selected", selected ? "true" : "false");
      option.title = label;
      return option;
    }

    renderReferences(query) {
      const result = this.search.searchReferences(
        this.references,
        query,
        this.selectedBranchValue
      );
      this.branchOptions.innerHTML = "";
      result.visible.forEach((reference, index) => {
        this.branchOptions.appendChild(this.buildOption(
          "branch",
          reference.full_name,
          reference.label,
          reference.full_name === this.selectedBranchValue,
          index
        ));
      });

      if (!this.references.some((reference) => reference.full_name === this.selectedBranchValue) &&
          result.visible.length > 0) {
        this.selectedBranchValue = result.visible[0].full_name;
      }
      const selectedIndex = result.visible.findIndex((reference) => (
        reference.full_name === this.selectedBranchValue
      ));
      this.setActiveOption("branch", selectedIndex >= 0 ? selectedIndex : (result.visible.length ? 0 : -1));
      const selected = this.references.find((reference) => (
        reference.full_name === this.selectedBranchValue
      ));
      this.branchValue.textContent = selected ? selected.label : "Select a ref";

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

    commitLabel(commit) {
      return commit.short_sha + " — " + (commit.subject || "").slice(0, 80);
    }

    renderCommits(query) {
      const result = this.search.searchCommits(this.commits, query, this.selectedCommitValue);
      this.commitOptions.innerHTML = "";
      result.visible.forEach((commit, index) => {
        this.commitOptions.appendChild(this.buildOption(
          "commit",
          commit.sha,
          this.commitLabel(commit),
          commit.sha === this.selectedCommitValue,
          index
        ));
      });

      if (!this.commits.some((commit) => commit.sha === this.selectedCommitValue) &&
          result.visible.length > 0) {
        this.selectedCommitValue = result.visible[0].sha;
      }
      const selectedIndex = result.visible.findIndex((commit) => commit.sha === this.selectedCommitValue);
      this.setActiveOption("commit", selectedIndex >= 0 ? selectedIndex : (result.visible.length ? 0 : -1));
      const selected = this.commits.find((commit) => commit.sha === this.selectedCommitValue);
      this.commitValue.textContent = selected ? this.commitLabel(selected) : "Select a commit";

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
      this.travelBtn.disabled = !this.selectedCommitValue;
    }

    async fetchBranches() {
      const request = this.startRequest("branchRequest");
      this.branchSearch.disabled = true;
      this.branchTrigger.disabled = true;
      this.branchValue.textContent = "Loading refs…";
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
        this.branchTrigger.disabled = this.references.length === 0;
        if ((data.errors || []).length > 0) this.showError(data.errors.join(" | "));
        if (this.selectedBranchValue) await this.fetchCommits(this.selectedBranchValue);
      } catch (error) {
        if (this.requestWasCancelled("branchRequest", request, error)) return;

        this.branchValue.textContent = "Refs unavailable";
        this.branchResults.textContent = "Refs unavailable";
        this.showError("branches: " + error.message);
      }
    }

    async fetchCommits(branch) {
      const request = this.startRequest("commitRequest");
      this.closeDropdown("commit", false);
      this.travelBtn.disabled = true;
      this.commitSearch.disabled = true;
      this.commitTrigger.disabled = true;
      this.commitValue.textContent = "Loading commits…";
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
        this.commitTrigger.disabled = this.commits.length === 0;
        if (data.error) {
          this.showError("commits: " + data.error);
        } else if (!this.activeRef) {
          this.setState();
        }
      } catch (error) {
        if (this.requestWasCancelled("commitRequest", request, error)) return;

        this.commitValue.textContent = "Commits unavailable";
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
      const sha = this.selectedCommitValue;
      if (!sha || !this.trustWarningAccepted()) return;

      this.setCookie("rails_wayback_ref", sha);
      if (this.selectedBranchValue) {
        this.setCookie("rails_wayback_branch", this.selectedBranchValue);
      }
      const url = new this.window.URL(this.window.location.href);
      url.searchParams.set("_wayback_ref", sha);
      if (this.selectedBranchValue) {
        url.searchParams.set("_wayback_branch", this.selectedBranchValue);
      }
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
