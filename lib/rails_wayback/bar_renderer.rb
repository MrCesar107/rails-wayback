# frozen_string_literal: true

require "json"
require "cgi"

module RailsWayback
  # Builds the HTML/CSS/JS payload that the middleware injects into
  # every HTML response so the developer can travel from any page of
  # their app without visiting a dedicated route.
  class BarRenderer
    def initialize(current_branch:, current_commit:, active_ref: nil, active_branch: nil,
                   engine_mount: "/rails-wayback", diff_info: nil)
      @current_branch = current_branch
      @current_commit = current_commit
      @active_ref = active_ref
      @active_branch = active_branch
      @engine_mount = engine_mount
      @diff_info = diff_info
    end

    def render
      <<~HTML
        <style data-rails-wayback>#{styles}</style>
        <div id="rails-wayback-bar" data-mount="#{escape(@engine_mount)}"
             data-branch="#{escape(@current_branch)}"
             data-commit="#{escape(@current_commit)}"
             data-active-ref="#{escape(@active_ref.to_s)}"
             data-active-branch="#{escape(@active_branch.to_s)}">
          <div class="rw-bar-inner">
            <div class="rw-field">
              <label>#{escape(branch_label)}</label>
              <select data-rw-branch></select>
            </div>
            <div class="rw-field rw-flex">
              <label>#{escape(commit_label)}</label>
              <select data-rw-commit></select>
            </div>
            <div class="rw-state" data-rw-state></div>
            <button type="button" data-rw-travel class="rw-btn rw-btn-primary">Travel</button>
            <button type="button" data-rw-reset  class="rw-btn rw-btn-ghost" hidden>Return to HEAD</button>
          </div>
          #{diff_summary_html}
        </div>
        <script data-rails-wayback>#{script}</script>
      HTML
    end

    private

    def branch_label
      @active_ref ? "Rendering branch" : "Current branch"
    end

    def commit_label
      @active_ref ? "Rendering commit" : "Current commit"
    end

    def escape(value)
      CGI.escapeHTML(value.to_s)
    end

    # Second row of the bar shown only while traveling. Tells the
    # developer whether the current page actually contains any changed
    # templates for the active ref, so they don't waste time refreshing
    # a page that has no diffs vs the ref they picked.
    def diff_summary_html
      return "" unless @diff_info

      changed  = Array(@diff_info[:changed_files])
      matched  = Array(@diff_info[:matched])
      total    = changed.size

      if total.zero?
        message = %(No view/asset diffs between HEAD and this ref.)
        css_class = "rw-diff rw-diff-neutral"
        list_html = ""
      elsif matched.any?
        message = %(#{matched.size} changed view#{"s" if matched.size != 1} rendered on this page.)
        css_class = "rw-diff rw-diff-match"
        list_html = diff_details("Matched on this page (#{matched.size})", matched) +
                    diff_details("All changed files (#{total})", changed)
      else
        message = %(No changed views on this page. #{total} file#{"s" if total != 1} differ elsewhere.)
        css_class = "rw-diff rw-diff-miss"
        list_html = diff_details("Changed files (#{total})", changed)
      end

      <<~HTML.strip
        <div class="#{css_class}">
          <span class="rw-diff-msg">#{escape(message)}</span>
          #{list_html}
        </div>
      HTML
    end

    def diff_details(summary, files)
      items = files.map { |f| %(<li>#{escape(f)}</li>) }.join
      <<~HTML.strip
        <details class="rw-diff-details">
          <summary>#{escape(summary)}</summary>
          <ul>#{items}</ul>
        </details>
      HTML
    end

    def styles
      <<~CSS
        #rails-wayback-bar {
          position: fixed; left: 0; right: 0; bottom: 0; z-index: 2147483000;
          font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
          font-size: 12px; color: #e6e9ef;
          background: rgba(15, 17, 21, 0.96);
          border-top: 1px solid #2a2f3a;
          box-shadow: 0 -8px 20px rgba(0,0,0,.35);
        }
        #rails-wayback-bar * { box-sizing: border-box; }
        #rails-wayback-bar .rw-bar-inner {
          display: flex; align-items: end; gap: 12px; padding: 8px 12px;
        }
        #rails-wayback-bar .rw-field { display: flex; flex-direction: column; gap: 3px; min-width: 180px; }
        #rails-wayback-bar .rw-flex { flex: 1; }
        #rails-wayback-bar label {
          color: #8a93a6; text-transform: uppercase; letter-spacing: .06em; font-size: 10px;
        }
        #rails-wayback-bar select {
          background: #0b0d12; color: #e6e9ef;
          border: 1px solid #2a2f3a; border-radius: 4px;
          padding: 5px 8px; font-family: inherit; font-size: 12px; width: 100%;
        }
        #rails-wayback-bar .rw-state { color: #8a93a6; font-size: 11px; margin: 0 4px; }
        #rails-wayback-bar .rw-state.rw-active { color: #ffd479; }
        #rails-wayback-bar .rw-btn {
          border: 0; border-radius: 4px; padding: 8px 14px; cursor: pointer;
          font-family: inherit; font-size: 12px; font-weight: 600;
        }
        #rails-wayback-bar .rw-btn-primary { background: #6ea8fe; color: #0b0d12; }
        #rails-wayback-bar .rw-btn-ghost   { background: transparent; color: #8a93a6; border: 1px solid #2a2f3a; }
        #rails-wayback-bar .rw-btn:disabled { opacity: .5; cursor: not-allowed; }
        #rails-wayback-bar .rw-diff {
          border-top: 1px solid #2a2f3a;
          padding: 6px 12px; font-size: 11px; color: #8a93a6;
          display: flex; align-items: center; gap: 10px; flex-wrap: wrap;
        }
        #rails-wayback-bar .rw-diff-match .rw-diff-msg { color: #7ee787; }
        #rails-wayback-bar .rw-diff-miss  .rw-diff-msg { color: #ffd479; }
        #rails-wayback-bar .rw-diff-neutral .rw-diff-msg { color: #8a93a6; }
        #rails-wayback-bar .rw-diff-details { color: #8a93a6; }
        #rails-wayback-bar .rw-diff-details summary {
          cursor: pointer; user-select: none;
        }
        #rails-wayback-bar .rw-diff-details[open] {
          flex-basis: 100%;
        }
        #rails-wayback-bar .rw-diff-details ul {
          margin: 6px 0 0; padding: 6px 10px; list-style: none;
          background: #0b0d12; border: 1px solid #2a2f3a; border-radius: 4px;
          max-height: 200px; overflow: auto;
          font-family: inherit; font-size: 11px;
        }
        #rails-wayback-bar .rw-diff-details li { padding: 2px 0; color: #c8cfdc; }
        body { padding-bottom: 56px !important; }
        body:has(#rails-wayback-bar .rw-diff) { padding-bottom: 88px !important; }
      CSS
    end

    def script
      <<~JS
        (function () {
          var bar = document.getElementById("rails-wayback-bar");
          if (!bar) return;

          var mount     = bar.dataset.mount;
          var headBranch = bar.dataset.branch;
          var headCommit = bar.dataset.commit;
          var activeRef  = bar.dataset.activeRef || "";
          var activeBranch = bar.dataset.activeBranch || "";
          // While traveling, reflect the ref's branch/commit in the
          // dropdowns instead of the developer's local HEAD, so the bar
          // matches what is actually being rendered.
          var selectedBranch = activeBranch || headBranch;
          var selectedCommit = activeRef || headCommit;

          var branchSel = bar.querySelector("[data-rw-branch]");
          var commitSel = bar.querySelector("[data-rw-commit]");
          var stateEl   = bar.querySelector("[data-rw-state]");
          var travelBtn = bar.querySelector("[data-rw-travel]");
          var resetBtn  = bar.querySelector("[data-rw-reset]");

          function setState() {
            if (activeRef) {
              var label = activeBranch
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

          function loadBranches() {
            fetch(mount + "/branches", { headers: { Accept: "application/json" } })
              .then(function (r) {
                if (!r.ok) throw new Error("HTTP " + r.status + " on /branches");
                return r.json();
              })
              .then(function (data) {
                branchSel.innerHTML = "";
                (data.branches || []).forEach(function (b) {
                  var opt = document.createElement("option");
                  opt.value = b; opt.textContent = b;
                  if (b === selectedBranch) opt.selected = true;
                  branchSel.appendChild(opt);
                });
                if ((data.errors || []).length > 0) showError(data.errors.join(" | "));
                if (branchSel.value) loadCommits(branchSel.value);
              })
              .catch(function (err) {
                showError("branches: " + err.message);
              });
          }

          function loadCommits(branch) {
            travelBtn.disabled = true;
            fetch(mount + "/commits/" + encodeURI(branch), { headers: { Accept: "application/json" } })
              .then(function (r) {
                if (!r.ok) throw new Error("HTTP " + r.status + " on /commits/" + branch);
                return r.json();
              })
              .then(function (data) {
                commitSel.innerHTML = "";
                (data.commits || []).forEach(function (c) {
                  var opt = document.createElement("option");
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

          function clearCookie(name) {
            document.cookie = name + "=; Path=/; Max-Age=0; SameSite=Lax";
          }

          // Travel is a *session*, not a one-off request: the ref lives
          // in a cookie so it survives every subsequent link click. The
          // URL params are added just so a first-time landing (or a
          // shared link) still works even before the cookie is set.
          function travel() {
            var sha = commitSel.value;
            if (!sha) return;
            setCookie("rails_wayback_ref", sha);
            if (branchSel.value) setCookie("rails_wayback_branch", branchSel.value);
            var url = new URL(window.location.href);
            url.searchParams.set("_wayback_ref", sha);
            if (branchSel.value) url.searchParams.set("_wayback_branch", branchSel.value);
            window.location.assign(url.toString());
          }

          function reset() {
            clearCookie("rails_wayback_ref");
            clearCookie("rails_wayback_branch");
            var url = new URL(window.location.href);
            url.searchParams.delete("_wayback_ref");
            url.searchParams.delete("_wayback_branch");
            window.location.assign(url.toString());
          }

          branchSel.addEventListener("change", function (e) { loadCommits(e.target.value); });
          travelBtn.addEventListener("click", travel);
          resetBtn.addEventListener("click", reset);

          setState();
          loadBranches();
        })();
      JS
    end
  end
end
