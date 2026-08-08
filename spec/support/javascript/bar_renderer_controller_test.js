const assert = require("node:assert/strict");
const Toolbar = require(process.argv[2]);
const search = require(process.argv[3]);

function field() {
  let innerHTML = "";
  return {
    children: [],
    classList: { add() {}, remove() {} },
    disabled: false,
    hidden: false,
    listeners: [],
    textContent: "",
    value: "",
    addEventListener(type, listener, options) {
      this.listeners.push({ type, listener, signal: options && options.signal });
    },
    appendChild(option) {
      this.children.push(option);
      if (option.selected || !this.value) this.value = option.value;
    },
    setAttribute() {},
    get innerHTML() { return innerHTML; },
    set innerHTML(value) {
      innerHTML = value;
      if (value === "") {
        this.children = [];
        this.value = "";
      }
    }
  };
}

const fields = {
  "[data-rw-branch]": field(),
  "[data-rw-commit]": field(),
  "[data-rw-branch-search]": field(),
  "[data-rw-commit-search]": field(),
  "[data-rw-branch-results]": field(),
  "[data-rw-commit-results]": field(),
  "[data-rw-state]": field(),
  "[data-rw-travel]": field(),
  "[data-rw-reset]": field()
};
const root = {
  dataset: {
    mount: "/rails-wayback",
    branch: "main",
    commit: "a".repeat(40),
    activeRef: "",
    activeBranch: "",
    refError: ""
  },
  querySelector(selector) { return fields[selector]; }
};
const document = {
  cookie: "",
  createElement() { return { selected: false, textContent: "", value: "" }; }
};
const window = {
  confirm() { return true; },
  location: {
    assign() {},
    href: "https://example.test/projects/1",
    origin: "https://example.test"
  },
  sessionStorage: { getItem() { return null; }, setItem() {} }
};
const pending = new Map();
const signals = [];
const response = (commits) => ({ ok: true, json: async () => ({ commits }) });
const fetch = (url, options) => {
  signals.push(options.signal);
  if (url.endsWith("/branches")) {
    return Promise.resolve({ ok: true, json: async () => ({ refs: [] }) });
  }
  return new Promise((resolve) => pending.set(url, resolve));
};

async function run() {
  const toolbar = new Toolbar(root, {
    AbortController,
    document,
    fetch,
    search,
    window
  });
  await toolbar.connect();

  const listenerSignals = Object.values(fields)
    .flatMap((element) => element.listeners.map((listener) => listener.signal));
  assert.equal(listenerSignals.length, 6);
  assert.ok(listenerSignals.every((signal) => signal && !signal.aborted));

  const first = toolbar.fetchCommits("refs/heads/first");
  const firstUrl = "/rails-wayback/commits/refs/heads/first";
  const firstSignal = signals.at(-1);
  const second = toolbar.fetchCommits("refs/heads/second");
  const secondUrl = "/rails-wayback/commits/refs/heads/second";
  assert.equal(firstSignal.aborted, true);

  pending.get(secondUrl)(response([{ sha: "2", short_sha: "2", subject: "second" }]));
  await second;
  pending.get(firstUrl)(response([{ sha: "1", short_sha: "1", subject: "first" }]));
  await first;
  assert.equal(toolbar.commits[0].sha, "2");

  toolbar.disconnect();
  assert.ok(listenerSignals.every((signal) => signal.aborted));
  assert.ok(signals.every((signal) => signal.aborted));
  process.stdout.write(JSON.stringify({ lifecycle: true, staleResponseIgnored: true }));
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
