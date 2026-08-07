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

  const branchSel = bar.querySelector("[data-rw-branch]");
  const commitSel = bar.querySelector("[data-rw-commit]");
  const stateEl = bar.querySelector("[data-rw-state]");
  const travelBtn = bar.querySelector("[data-rw-travel]");
  const resetBtn = bar.querySelector("[data-rw-reset]");

  function setState() {
    if (refError) {
      stateEl.textContent = "Travel rejected";
      stateEl.classList.add("rw-active");
      resetBtn.hidden = false;
    } else if (activeRef) {
      const label = activeBranch
        ? activeBranch + "@" + activeRef.slice(0, 7)
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

  function fetchBranches() {
    fetch(mount + "/branches", { headers: { Accept: "application/json" } })
      .then(function (r) {
        if (!r.ok) throw new Error("HTTP " + r.status + " on /branches");
        return r.json();
      })
      .then(function (data) {
        branchSel.innerHTML = "";
        (data.branches || []).forEach(function (b) {
          const opt = document.createElement("option");
          opt.value = b;
          opt.textContent = b;
          if (b === selectedBranch) opt.selected = true;
          branchSel.appendChild(opt);
        });
        if ((data.errors || []).length > 0) showError(data.errors.join(" | "));
        if (branchSel.value) fetchCommits(branchSel.value);
      })
      .catch(function (err) {
        showError("branches: " + err.message);
      });
  }

  function fetchCommits(branch) {
    travelBtn.disabled = true;
    fetch(mount + "/commits/" + encodeURI(branch), { headers: { Accept: "application/json" } })
      .then(function (r) {
        if (!r.ok) throw new Error("HTTP " + r.status + " on /commits/" + branch);
        return r.json();
      })
      .then(function (data) {
        commitSel.innerHTML = "";
        (data.commits || []).forEach(function (c) {
          const opt = document.createElement("option");
          opt.value = c.sha;
          opt.textContent = c.short_sha + " — " + (c.subject || "").slice(0, 80);
          if (c.sha === selectedCommit) opt.selected = true;
          commitSel.appendChild(opt);
        });
        if (data.error) {
          showError("commits: " + data.error);
        } else if (!activeRef) {
          setState();
        }
        travelBtn.disabled = !commitSel.value;
      })
      .catch(function (err) {
        showError("commits: " + err.message);
      });
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

  branchSel.addEventListener("change", function (e) { fetchCommits(e.target.value); });
  travelBtn.addEventListener("click", travel);
  resetBtn.addEventListener("click", reset);

  setState();
  fetchBranches();
})();
