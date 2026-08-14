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
      this.Combobox = options.Combobox || runtimeWindow.RailsWaybackCombobox;
      this.AbortController = options.AbortController || runtimeWindow.AbortController;
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
      this.travelBtn.disabled = true;
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
      this.initialBranch = this.activeBranch || this.headBranch;
      this.initialCommit = this.activeRef || this.headCommit;
    }

    findElements() {
      this.stateEl = this.element.querySelector("[data-rw-state]");
      this.travelBtn = this.element.querySelector("[data-rw-travel]");
      this.resetBtn = this.element.querySelector("[data-rw-reset]");
      this.travelForm = this.element.querySelector("[data-rw-travel-form]");
      this.resetForm = this.element.querySelector("[data-rw-reset-form]");
      this.nativeControls = this.element.querySelector("[data-rw-native]");
      this.enhancedControls = this.element.querySelector("[data-rw-enhanced]");
      this.branchNative = this.element.querySelector("[data-rw-branch-native]");
      this.commitNative = this.element.querySelector("[data-rw-commit-native]");
      this.trustConfirmation = this.element.querySelector("[data-rw-trust-confirmation]");
      this.trustField = this.element.querySelector("[data-rw-trust-field]");

      this.branchBox = new this.Combobox(
        this.element.querySelector("[data-rw-branch-combobox]"),
        {
          document: this.document,
          kind: "branch",
          noun: "ref",
          emptyLabel: "Select a ref",
          selectedValue: this.initialBranch,
          searchItems: (items, query, selected) => (
            this.search.searchReferences(items, query, selected)
          ),
          valueOf: (reference) => reference.full_name,
          labelOf: (reference) => reference.label,
          onOpen: () => this.commitBox.close(false),
          onSelect: (value, changed) => this.selectBranch(value, changed)
        }
      );
      this.commitBox = new this.Combobox(
        this.element.querySelector("[data-rw-commit-combobox]"),
        {
          document: this.document,
          kind: "commit",
          noun: "commit",
          emptyLabel: "Select a commit",
          selectedValue: this.initialCommit,
          searchItems: (items, query, selected) => (
            this.search.searchCommits(items, query, selected)
          ),
          valueOf: (commit) => commit.sha,
          labelOf: (commit) => this.commitLabel(commit),
          onOpen: () => this.branchBox.close(false),
          onSelect: (value) => {
            this.commitNative.value = value;
            this.travelBtn.disabled = !value;
          }
        }
      );
    }

    bindEvents(signal) {
      this.branchBox.connect(signal);
      this.commitBox.connect(signal);
      const options = { signal: signal };
      this.travelForm.addEventListener("submit", (event) => this.confirmTravel(event), options);
    }

    selectBranch(value, changed) {
      if (!changed) return;

      this.branchNative.value = value;
      this.travelBtn.disabled = true;
      this.fetchCommits(value, "");
    }

    setState() {
      if (this.refError) {
        this.stateEl.textContent = "Travel rejected";
        this.stateEl.classList.add("rw-active");
        this.resetForm.hidden = false;
      } else if (this.activeRef) {
        const label = this.activeBranch
          ? this.referenceLabel(this.activeBranch) + "@" + this.activeRef.slice(0, 7)
          : this.activeRef.slice(0, 7);
        this.stateEl.textContent = "Traveling: " + label;
        this.stateEl.classList.add("rw-active");
        this.resetForm.hidden = false;
      } else {
        this.stateEl.textContent = "Live";
        this.stateEl.classList.remove("rw-active");
        this.resetForm.hidden = true;
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

    commitLabel(commit) {
      return commit.short_sha + " — " + (commit.subject || "").slice(0, 80);
    }

    async fetchBranches() {
      this.branchBox.setLoading("Loading refs…", "Loading refs");

      try {
        const data = await this.fetchJSON("branchRequest", "/references");
        if (!data) return;

        const references = data.refs || (data.branches || []).map((branch) => ({
          full_name: branch,
          name: branch,
          label: branch,
          type: "branch"
        }));
        const initial = references.find((reference) => (
          this.referenceMatchesSelection(reference, this.initialBranch)
        ));
        const selected = initial ? initial.full_name : "";
        this.branchBox.setItems(references, selected);
        this.replaceNativeOptions(
          this.branchNative,
          references,
          (reference) => reference.full_name,
          (reference) => reference.label,
          this.branchBox.value
        );
        if ((data.errors || []).length > 0) this.showError(data.errors.join(" | "));
        if (this.branchBox.value && await this.fetchCommits(this.branchBox.value, this.initialCommit)) {
          this.activateEnhancement();
        }
      } catch (error) {
        this.branchBox.setUnavailable("Refs unavailable");
        this.showError("references: " + error.message);
      }
    }

    async fetchCommits(branch, selectedCommit) {
      this.travelBtn.disabled = true;
      this.commitBox.setLoading("Loading commits…", "Loading commits");

      try {
        const path = "/commits?reference=" + encodeURIComponent(branch);
        const data = await this.fetchJSON("commitRequest", path, "/commits?reference=" + branch);
        if (!data) return false;

        const commits = data.commits || [];
        this.commitBox.setItems(commits, selectedCommit);
        this.replaceNativeOptions(
          this.commitNative,
          commits,
          (commit) => commit.sha,
          (commit) => this.commitLabel(commit),
          this.commitBox.value
        );
        this.travelBtn.disabled = !this.commitBox.value;
        if (data.error) {
          this.showError("commits: " + data.error);
        } else if (!this.activeRef) {
          this.setState();
        }
        return true;
      } catch (error) {
        this.commitBox.setUnavailable("Commits unavailable");
        this.showError("commits: " + error.message);
        return false;
      }
    }

    replaceNativeOptions(select, items, valueOf, labelOf, selectedValue) {
      select.innerHTML = "";
      items.forEach((item) => {
        const option = this.document.createElement("option");
        option.value = valueOf(item);
        option.textContent = labelOf(item);
        option.selected = option.value === selectedValue;
        select.appendChild(option);
      });
      select.value = selectedValue || "";
    }

    activateEnhancement() {
      this.nativeControls.hidden = true;
      this.enhancedControls.hidden = false;
      this.trustConfirmation.required = false;
      this.trustField.hidden = true;
    }

    async fetchJSON(property, path, errorPath) {
      const request = this.startRequest(property);
      try {
        const response = await this.fetch(this.mount + path, {
          headers: { Accept: "application/json" },
          signal: request.signal
        });
        if (!response.ok) throw new Error("HTTP " + response.status + " on " + (errorPath || path));

        const data = await response.json();
        return this.requestIsCurrent(property, request) ? data : null;
      } catch (error) {
        if (error.name === "AbortError" || !this.requestIsCurrent(property, request)) return null;
        throw error;
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

    confirmTravel(event) {
      const accepted = this.commitNative.value && this.trustWarningAccepted();
      this.trustConfirmation.checked = Boolean(accepted);
      if (!accepted) event.preventDefault();
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

  }

  return RailsWaybackToolbar;
});
