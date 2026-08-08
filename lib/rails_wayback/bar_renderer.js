(function () {
  const bar = document.getElementById("rails-wayback-bar");
  if (!bar) return;

  const mount = bar.dataset.mount;
  const headBranch = bar.dataset.branch;
  const headCommit = bar.dataset.commit;
  const activeRef = bar.dataset.activeRef || "";
  const activeBranch = bar.dataset.activeBranch || "";
  const refError = bar.dataset.refError || "";

  // While traveling, reflect the ref's branch/commit in the
  // dropdowns instead of the developer's local HEAD, so the bar
  // matches what is actually being rendered.
  const selectedBranch = activeBranch || headBranch;
  const selectedCommit = activeRef || headCommit;
  const search = window.RailsWaybackSearch;

  const branchSel = bar.querySelector("[data-rw-branch]");
  const commitSel = bar.querySelector("[data-rw-commit]");
  const branchSearch = bar.querySelector("[data-rw-branch-search]");
  const commitSearch = bar.querySelector("[data-rw-commit-search]");
  const branchResults = bar.querySelector("[data-rw-branch-results]");
  const commitResults = bar.querySelector("[data-rw-commit-results]");
  const stateEl = bar.querySelector("[data-rw-state]");
  const travelBtn = bar.querySelector("[data-rw-travel]");
  const resetBtn = bar.querySelector("[data-rw-reset]");
  let references = [];
  let commits = [];
  let selectedBranchValue = selectedBranch;
  let selectedCommitValue = selectedCommit;

  function setState() {
    if (refError) {
      stateEl.textContent = "Travel rejected";
      stateEl.classList.add("rw-active");
      resetBtn.hidden = false;
    } else if (activeRef) {
      const label = activeBranch
        ? referenceLabel(activeBranch) + "@" + activeRef.slice(0, 7)
        : activeRef.slice(0, 7);
      stateEl.textContent = "Traveling: " + label;
      stateEl.classList.add("rw-active");
      resetBtn.hidden = false;
    } else {
      stateEl.textContent = "Live";
      stateEl.classList.remove("rw-active");
      resetBtn.hidden = true;
    }
  }

  function showError(msg) {
    stateEl.textContent = msg;
    stateEl.classList.add("rw-active");
  }

  function referenceLabel(reference) {
    if (reference.indexOf("refs/heads/") === 0) return reference.slice(11);
    if (reference.indexOf("refs/remotes/") === 0) return reference.slice(13);
    if (reference.indexOf("refs/tags/") === 0) return "tag:" + reference.slice(10);
    return reference;
  }

  function referenceMatchesSelection(reference, selection) {
    return reference.full_name === selection ||
      reference.name === selection ||
      reference.label === selection;
  }

  function resultMessage(count, noun, query, selectionRetained) {
    if (!query.trim()) return count + " " + noun + (count === 1 ? "" : "s") + " loaded";
    if (count > 0) return count + " matching " + noun + (count === 1 ? "" : "s");
    return "No matching " + noun + "s" +
      (selectionRetained ? "; current selection retained" : "");
  }

  function renderReferences(query) {
    const result = search.searchReferences(references, query, selectedBranchValue);
    branchSel.innerHTML = "";
    result.visible.forEach(function (reference) {
      const opt = document.createElement("option");
      opt.value = reference.full_name;
      opt.textContent = reference.label;
      opt.selected = reference.full_name === selectedBranchValue;
      branchSel.appendChild(opt);
    });

    if (!branchSel.value && result.visible.length > 0) {
      selectedBranchValue = result.visible[0].full_name;
      branchSel.value = selectedBranchValue;
    }
    const retained = result.visible.length > result.matches.length;
    branchResults.textContent = resultMessage(result.matches.length, "ref", query, retained);
    branchSearch.setAttribute("aria-invalid", result.matches.length === 0 && query.trim() ? "true" : "false");
  }

  function renderCommits(query) {
    const result = search.searchCommits(commits, query, selectedCommitValue);
    commitSel.innerHTML = "";
    result.visible.forEach(function (commit) {
      const opt = document.createElement("option");
      opt.value = commit.sha;
      opt.textContent = commit.short_sha + " — " + (commit.subject || "").slice(0, 80);
      opt.selected = commit.sha === selectedCommitValue;
      commitSel.appendChild(opt);
    });

    if (!commitSel.value && result.visible.length > 0) {
      selectedCommitValue = result.visible[0].sha;
      commitSel.value = selectedCommitValue;
    }
    const retained = result.visible.length > result.matches.length;
    commitResults.textContent = resultMessage(result.matches.length, "commit", query, retained);
    commitSearch.setAttribute("aria-invalid", result.matches.length === 0 && query.trim() ? "true" : "false");
    travelBtn.disabled = !commitSel.value;
  }

  async function fetchBranches() {
    branchSearch.disabled = true;
    branchSel.disabled = true;
    branchResults.textContent = "Loading refs";
    try {
      const response = await fetch(mount + "/branches", {
        headers: { Accept: "application/json" }
      });
      if (!response.ok) throw new Error("HTTP " + response.status + " on /branches");

      const data = await response.json();
      references = data.refs || (data.branches || []).map(function (branch) {
        return { full_name: branch, name: branch, label: branch, type: "branch" };
      });
      const initial = references.find(function (reference) {
        return referenceMatchesSelection(reference, selectedBranchValue);
      });
      selectedBranchValue = initial ? initial.full_name : references[0] && references[0].full_name;
      renderReferences(branchSearch.value);
      branchSearch.disabled = references.length === 0;
      branchSel.disabled = references.length === 0;
      if ((data.errors || []).length > 0) showError(data.errors.join(" | "));
      if (branchSel.value) await fetchCommits(branchSel.value);
    } catch (error) {
      branchResults.textContent = "Refs unavailable";
      showError("branches: " + error.message);
    }
  }

  async function fetchCommits(branch) {
    travelBtn.disabled = true;
    commitSearch.disabled = true;
    commitSel.disabled = true;
    commitResults.textContent = "Loading commits";
    try {
      const response = await fetch(mount + "/commits/" + encodeURI(branch), {
        headers: { Accept: "application/json" }
      });
      if (!response.ok) {
        throw new Error("HTTP " + response.status + " on /commits/" + branch);
      }

      const data = await response.json();
      commits = data.commits || [];
      if (!commits.some(function (commit) { return commit.sha === selectedCommitValue; })) {
        selectedCommitValue = commits[0] && commits[0].sha;
      }
      renderCommits(commitSearch.value);
      commitSearch.disabled = commits.length === 0;
      commitSel.disabled = commits.length === 0;
      if (data.error) {
        showError("commits: " + data.error);
      } else if (!activeRef) {
        setState();
      }
    } catch (error) {
      commitResults.textContent = "Commits unavailable";
      showError("commits: " + error.message);
    }
  }

  function setCookie(name, value) {
    document.cookie = name + "=" + encodeURIComponent(value) + "; Path=/; SameSite=Lax";
  }

  // Travel is a *session*, not a one-off request: the ref lives
  // in a cookie so it survives every subsequent link click. The
  // URL params are added just so a first-time landing (or a
  // shared link) still works even before the cookie is set.
  function travel() {
    const sha = commitSel.value;
    if (!sha) return;
    if (!trustWarningAccepted()) return;
    setCookie("rails_wayback_ref", sha);
    if (branchSel.value) setCookie("rails_wayback_branch", branchSel.value);
    const url = new URL(window.location.href);
    url.searchParams.set("_wayback_ref", sha);
    if (branchSel.value) url.searchParams.set("_wayback_branch", branchSel.value);
    window.location.assign(url.toString());
  }

  function trustWarningAccepted() {
    const key = "rails-wayback.trust-warning-accepted";
    try {
      if (window.sessionStorage.getItem(key) === "true") return true;
    } catch (_error) {
      // Storage may be unavailable; confirmation still protects this action.
    }

    const accepted = window.confirm(
      "Historical templates execute Ruby inside this Rails process. " +
      "Continue only if you trust this commit."
    );
    if (accepted) {
      try { window.sessionStorage.setItem(key, "true"); } catch (_error) { /* no-op */ }
    }
    return accepted;
  }

  function reset() {
    const url = new URL(window.location.href);
    url.searchParams.delete("_wayback_ref");
    url.searchParams.delete("_wayback_branch");

    const resetUrl = new URL(mount + "/reset", window.location.origin);
    resetUrl.searchParams.set("return_to", url.pathname + url.search + url.hash);
    window.location.assign(resetUrl.toString());
  }

  branchSearch.addEventListener("input", function (e) { renderReferences(e.target.value); });
  commitSearch.addEventListener("input", function (e) { renderCommits(e.target.value); });
  branchSel.addEventListener("change", function (e) {
    selectedBranchValue = e.target.value;
    selectedCommitValue = "";
    branchSearch.value = "";
    commitSearch.value = "";
    renderReferences("");
    fetchCommits(selectedBranchValue);
  });
  commitSel.addEventListener("change", function (e) { selectedCommitValue = e.target.value; });
  travelBtn.addEventListener("click", travel);
  resetBtn.addEventListener("click", reset);

  setState();
  fetchBranches();
})();
