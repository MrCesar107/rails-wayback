const assert = require("node:assert/strict");
const Toolbar = require(process.argv[2]);
const search = require(process.argv[3]);
const Combobox = require(process.argv[4]);

function element(document, dataset) {
  let innerHTML = "";
  const attributes = new Map();
  const listeners = [];
  const node = {
    attributes,
    children: [],
    classList: { add() {}, remove() {} },
    checked: false,
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
        defaultPrevented: false,
        key: "",
        preventDefault() { this.defaultPrevented = true; },
        target: this
      }, properties);
      listeners.filter((entry) => entry.type === type).forEach((entry) => entry.listener(event));
      return event;
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

function fixture(fetch, overrides) {
  const options = overrides || {};
  const cookies = [];
  const document = {
    activeElement: null,
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
  Object.defineProperty(document, "cookie", {
    get() { return cookies.at(-1) || ""; },
    set(value) { cookies.push(value); }
  });
  const fields = {};
  [
    "branch-combobox", "branch-trigger", "branch-value", "branch-dropdown",
    "branch-search", "branch-options", "branch-results", "commit-combobox",
    "commit-trigger", "commit-value", "commit-dropdown", "commit-search",
    "commit-options", "commit-results", "state", "travel", "reset",
    "travel-form", "reset-form", "native", "enhanced", "branch-native", "commit-native",
    "trust-confirmation", "trust-field"
  ].forEach((name) => { fields[`[data-rw-${name}]`] = element(document); });
  fields["[data-rw-branch-dropdown]"].hidden = true;
  fields["[data-rw-commit-dropdown]"].hidden = true;
  fields["[data-rw-enhanced]"].hidden = true;

  ["branch", "commit"].forEach((kind) => {
    const combobox = fields[`[data-rw-${kind}-combobox]`];
    const scopedFields = {
      "[data-rw-trigger]": fields[`[data-rw-${kind}-trigger]`],
      "[data-rw-value]": fields[`[data-rw-${kind}-value]`],
      "[data-rw-dropdown]": fields[`[data-rw-${kind}-dropdown]`],
      "[data-rw-search]": fields[`[data-rw-${kind}-search]`],
      "[data-rw-options]": fields[`[data-rw-${kind}-options]`],
      "[data-rw-results]": fields[`[data-rw-${kind}-results]`]
    };
    combobox.querySelector = (selector) => scopedFields[selector];
    combobox.contains = (target) => (
      target === combobox || Object.values(scopedFields).some((field) => field.contains(target))
    );
  });

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

  const assignedUrls = [];
  const storage = new Map();
  const window = {
    URL,
    confirm: options.confirm || (() => true),
    location: {
      assign(url) { assignedUrls.push(url); },
      href: "https://example.test/projects/1",
      origin: "https://example.test"
    },
    sessionStorage: {
      getItem(key) { return storage.get(key) || null; },
      setItem(key, value) { storage.set(key, value); }
    }
  };
  return {
    assignedUrls,
    cookies,
    document,
    fields,
    storage,
    window,
    toolbar: new Toolbar(root, { AbortController, Combobox, document, fetch, search, window })
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
    if (url.endsWith("/references")) return response({ refs });
    const branch = new URL(url, "https://example.test").searchParams.get("reference");
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
  assert.equal(toolbar.branchBox.value, "refs/heads/feature/search");
  assert.equal(branchDropdown.hidden, true);
  assert.equal(document.activeElement, branchTrigger);
  assert.equal(fields["[data-rw-branch-value]"].textContent, "feature/search");
  assert.equal(fields["[data-rw-commit-value]"].textContent, "ccccccc — Feature result");
  assert.equal(fields["[data-rw-branch-native]"].value, "refs/heads/feature/search");
  assert.equal(fields["[data-rw-commit-native]"].value, "c".repeat(40));

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
    if (url.endsWith("/references")) return Promise.resolve(response({ refs: [] }));
    return new Promise((resolve) => pending.set(url, resolve));
  };
  const { toolbar } = fixture(fetch);
  await toolbar.connect();

  const first = toolbar.fetchCommits("refs/heads/first");
  const firstUrl = "/rails-wayback/commits?reference=refs%2Fheads%2Ffirst";
  const firstSignal = signals.at(-1);
  const second = toolbar.fetchCommits("refs/heads/second");
  const secondUrl = "/rails-wayback/commits?reference=refs%2Fheads%2Fsecond";
  assert.equal(firstSignal.aborted, true);

  pending.get(secondUrl)(response({ commits: [{ sha: "2", short_sha: "2", subject: "second" }] }));
  await second;
  pending.get(firstUrl)(response({ commits: [{ sha: "1", short_sha: "1", subject: "first" }] }));
  await first;
  assert.equal(toolbar.commitBox.value, "2");
  toolbar.disconnect();
  assert.ok(signals.every((signal) => signal.aborted));
}

async function testFailuresAndEmptyResults() {
  const failed = fixture(async () => ({ ok: false, status: 503 }));
  await failed.toolbar.connect();
  assert.equal(failed.fields["[data-rw-branch-value]"].textContent, "Refs unavailable");
  assert.equal(failed.fields["[data-rw-branch-results]"].textContent, "Refs unavailable");
  assert.equal(failed.fields["[data-rw-state]"].textContent, "references: HTTP 503 on /references");
  assert.equal(failed.fields["[data-rw-native]"].hidden, false);
  assert.equal(failed.fields["[data-rw-enhanced]"].hidden, true);

  const empty = fixture(async () => response({ refs: [] }));
  await empty.toolbar.connect();
  assert.equal(empty.fields["[data-rw-branch-value]"].textContent, "Select a ref");
  assert.equal(empty.fields["[data-rw-branch-trigger]"].disabled, true);
}

async function testServerOwnedTravelSubmission() {
  const refs = [{ full_name: "refs/heads/main", name: "main", label: "main", type: "branch" }];
  const commits = [{ sha: "a".repeat(40), short_sha: "aaaaaaa", subject: "Current work" }];
  const fetch = async (url) => response(url.endsWith("/references") ? { refs } : { commits });
  let confirmations = 0;
  const accepted = fixture(fetch, { confirm() { confirmations += 1; return true; } });
  await accepted.toolbar.connect();

  const firstSubmit = accepted.fields["[data-rw-travel-form]"].dispatch("submit");
  const secondSubmit = accepted.fields["[data-rw-travel-form]"].dispatch("submit");
  assert.equal(confirmations, 1);
  assert.equal(firstSubmit.defaultPrevented, false);
  assert.equal(secondSubmit.defaultPrevented, false);
  assert.equal(accepted.fields["[data-rw-trust-confirmation]"].checked, true);
  assert.equal(accepted.cookies.length, 0);
  assert.equal(accepted.assignedUrls.length, 0);
  assert.equal(accepted.fields["[data-rw-native]"].hidden, true);
  assert.equal(accepted.fields["[data-rw-enhanced]"].hidden, false);
  assert.equal(accepted.fields["[data-rw-trust-field]"].hidden, true);
  assert.equal(accepted.fields["[data-rw-trust-confirmation]"].required, false);

  const rejected = fixture(fetch, { confirm() { return false; } });
  await rejected.toolbar.connect();
  const rejectedSubmit = rejected.fields["[data-rw-travel-form]"].dispatch("submit");
  assert.equal(rejectedSubmit.defaultPrevented, true);
  assert.equal(rejected.fields["[data-rw-trust-confirmation]"].checked, false);
  assert.equal(rejected.cookies.length, 0);
  assert.equal(rejected.assignedUrls.length, 0);
}

async function testReconnect() {
  let branchLoads = 0;
  const fetch = async (url) => {
    if (url.endsWith("/references")) branchLoads += 1;
    return response({ refs: [] });
  };
  const { toolbar } = fixture(fetch);
  await toolbar.connect();
  toolbar.disconnect();
  await toolbar.connect();
  assert.equal(branchLoads, 2);
}

async function run() {
  await testSearchableDropdowns();
  await testStaleResponse();
  await testFailuresAndEmptyResults();
  await testServerOwnedTravelSubmission();
  await testReconnect();
  process.stdout.write(JSON.stringify({
    errorsAndEmptyResults: true,
    searchableDropdowns: true,
    keyboardSelection: true,
    lifecycle: true,
    navigationAndTrust: true,
    reconnect: true,
    staleResponseIgnored: true
  }));
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
