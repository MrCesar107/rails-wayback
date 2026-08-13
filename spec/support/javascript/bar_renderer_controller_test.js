const assert = require("node:assert/strict");
const Toolbar = require(process.argv[2]);
const search = require(process.argv[3]);

function element(document, dataset) {
  let innerHTML = "";
  const attributes = new Map();
  const listeners = [];
  const node = {
    attributes,
    children: [],
    classList: { add() {}, remove() {} },
    dataset: dataset || {},
    disabled: false,
    hidden: false,
    listeners,
    parentNode: null,
    textContent: "",
    value: "",
    addEventListener(type, listener, options) {
      listeners.push({ type, listener, signal: options && options.signal });
    },
    appendChild(child) {
      child.parentNode = this;
      this.children.push(child);
      return child;
    },
    contains(target) {
      return target === this || this.children.some((child) => child.contains(target));
    },
    dispatch(type, properties) {
      const event = Object.assign({
        currentTarget: this,
        key: "",
        preventDefault() {},
        target: this
      }, properties);
      listeners.filter((entry) => entry.type === type).forEach((entry) => entry.listener(event));
    },
    focus() { document.activeElement = this; },
    getAttribute(name) { return attributes.get(name) || null; },
    removeAttribute(name) { attributes.delete(name); },
    setAttribute(name, value) { attributes.set(name, String(value)); },
    get innerHTML() { return innerHTML; },
    set innerHTML(value) {
      innerHTML = value;
      if (value === "") this.children = [];
    }
  };
  return node;
}

function fixture(fetch) {
  const document = {
    activeElement: null,
    cookie: "",
    listeners: [],
    addEventListener(type, listener, options) {
      this.listeners.push({ type, listener, signal: options && options.signal });
    },
    createElement() { return element(this); },
    dispatch(type, properties) {
      const event = Object.assign({ target: this }, properties);
      this.listeners.filter((entry) => entry.type === type).forEach((entry) => entry.listener(event));
    }
  };
  const fields = {};
  [
    "branch-combobox", "branch-trigger", "branch-value", "branch-dropdown",
    "branch-search", "branch-options", "branch-results", "commit-combobox",
    "commit-trigger", "commit-value", "commit-dropdown", "commit-search",
    "commit-options", "commit-results", "state", "travel", "reset"
  ].forEach((name) => { fields[`[data-rw-${name}]`] = element(document); });
  fields["[data-rw-branch-dropdown]"].hidden = true;
  fields["[data-rw-commit-dropdown]"].hidden = true;

  const root = element(document);
  root.dataset = {
    mount: "/rails-wayback",
    branch: "main",
    commit: "a".repeat(40),
    activeRef: "",
    activeBranch: "",
    refError: ""
  };
  root.querySelector = (selector) => fields[selector];
  root.contains = (target) => target === root || Object.values(fields).some((field) => field.contains(target));

  const window = {
    confirm() { return true; },
    location: {
      assign() {},
      href: "https://example.test/projects/1",
      origin: "https://example.test"
    },
    sessionStorage: { getItem() { return null; }, setItem() {} }
  };
  return {
    document,
    fields,
    toolbar: new Toolbar(root, { AbortController, document, fetch, search, window })
  };
}

function response(payload) {
  return { ok: true, json: async () => payload };
}

async function settle() {
  await new Promise((resolve) => setImmediate(resolve));
}

async function testSearchableDropdowns() {
  const refs = [
    { full_name: "refs/heads/main", name: "main", label: "main", type: "branch" },
    { full_name: "refs/heads/feature/search", name: "feature/search", label: "feature/search", type: "branch" }
  ];
  const commits = {
    "refs/heads/main": [
      { sha: "a".repeat(40), short_sha: "aaaaaaa", subject: "Current work" },
      { sha: "b".repeat(40), short_sha: "bbbbbbb", subject: "Add toolbar search" }
    ],
    "refs/heads/feature/search": [
      { sha: "c".repeat(40), short_sha: "ccccccc", subject: "Feature result" }
    ]
  };
  const fetch = async (url) => {
    if (url.endsWith("/branches")) return response({ refs });
    const branch = url.slice(url.indexOf("/commits/") + 9);
    return response({ commits: commits[branch] || [] });
  };
  const { document, fields, toolbar } = fixture(fetch);
  await toolbar.connect();

  const branchTrigger = fields["[data-rw-branch-trigger]"];
  const branchDropdown = fields["[data-rw-branch-dropdown]"];
  const branchSearch = fields["[data-rw-branch-search]"];
  const branchOptions = fields["[data-rw-branch-options]"];
  assert.equal(fields["[data-rw-branch-value]"].textContent, "main");
  assert.equal(branchTrigger.disabled, false);

  branchTrigger.dispatch("click");
  assert.equal(branchDropdown.hidden, false);
  assert.equal(branchTrigger.getAttribute("aria-expanded"), "true");
  assert.equal(document.activeElement, branchSearch);

  branchSearch.value = "feature";
  branchSearch.dispatch("input");
  assert.deepEqual(branchOptions.children.map((option) => option.textContent), ["main", "feature/search"]);
  branchSearch.dispatch("keydown", { key: "ArrowDown" });
  branchSearch.dispatch("keydown", { key: "Enter" });
  await settle();
  assert.equal(toolbar.selectedBranchValue, "refs/heads/feature/search");
  assert.equal(branchDropdown.hidden, true);
  assert.equal(document.activeElement, branchTrigger);
  assert.equal(fields["[data-rw-branch-value]"].textContent, "feature/search");
  assert.equal(fields["[data-rw-commit-value]"].textContent, "ccccccc — Feature result");

  const commitTrigger = fields["[data-rw-commit-trigger]"];
  const commitDropdown = fields["[data-rw-commit-dropdown]"];
  commitTrigger.dispatch("click");
  assert.equal(commitDropdown.hidden, false);
  fields["[data-rw-commit-search]"].dispatch("keydown", { key: "Escape" });
  assert.equal(commitDropdown.hidden, true);
  assert.equal(document.activeElement, commitTrigger);

  branchTrigger.dispatch("click");
  document.dispatch("click", { target: element(document) });
  assert.equal(branchDropdown.hidden, true);

  toolbar.disconnect();
  const listenerSignals = Object.values(fields)
    .flatMap((field) => field.listeners.map((listener) => listener.signal))
    .concat(document.listeners.map((listener) => listener.signal));
  assert.ok(listenerSignals.length > 0);
  assert.ok(listenerSignals.every((signal) => signal && signal.aborted));
}

async function testStaleResponse() {
  const pending = new Map();
  const signals = [];
  const fetch = (url, options) => {
    signals.push(options.signal);
    if (url.endsWith("/branches")) return Promise.resolve(response({ refs: [] }));
    return new Promise((resolve) => pending.set(url, resolve));
  };
  const { toolbar } = fixture(fetch);
  await toolbar.connect();

  const first = toolbar.fetchCommits("refs/heads/first");
  const firstUrl = "/rails-wayback/commits/refs/heads/first";
  const firstSignal = signals.at(-1);
  const second = toolbar.fetchCommits("refs/heads/second");
  const secondUrl = "/rails-wayback/commits/refs/heads/second";
  assert.equal(firstSignal.aborted, true);

  pending.get(secondUrl)(response({ commits: [{ sha: "2", short_sha: "2", subject: "second" }] }));
  await second;
  pending.get(firstUrl)(response({ commits: [{ sha: "1", short_sha: "1", subject: "first" }] }));
  await first;
  assert.equal(toolbar.commits[0].sha, "2");
  toolbar.disconnect();
  assert.ok(signals.every((signal) => signal.aborted));
}

async function run() {
  await testSearchableDropdowns();
  await testStaleResponse();
  process.stdout.write(JSON.stringify({
    searchableDropdowns: true,
    keyboardSelection: true,
    lifecycle: true,
    staleResponseIgnored: true
  }));
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
