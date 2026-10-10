import assert from "node:assert/strict";
import test from "node:test";
import { File } from "node:buffer";
import { ArchiveChecksum } from "../../app-phoenix/assets/js/hooks/archive_checksum.js";
import { prepareFile } from "../../app-phoenix/assets/js/uploads/prepare_file.js";
import { Direct } from "../../app-phoenix/assets/js/uploaders/direct.js";

const flush = () => new Promise((resolve) => setImmediate(resolve));

test("cancelled preparation cannot push a checksum or complete a replacement entry", async () => {
  let release;
  const file = {
    size: 3,
    _phxRef: "old",
    slice: () => ({
      arrayBuffer: () =>
        new Promise((resolve) => {
          release = resolve;
        }),
    }),
  };
  const pushed = [];
  const listeners = new Map();
  const hook = Object.assign(Object.create(ArchiveChecksum), {
    el: {
      dataset: {},
      querySelector: () => null,
      addEventListener: (name, fn) => listeners.set(name, fn),
      removeEventListener: (name) => listeners.delete(name),
    },
    pushEvent: (...args) => pushed.push(args),
  });
  hook.mounted();
  const digest = hook.digest(file);
  await flush();
  hook.destroyed();
  release(new Uint8Array([1, 2, 3]).buffer);
  await digest;
  assert.deepEqual(pushed, []);
  assert.equal(listeners.size, 0);
});

test("bounded preparation streams chunks and falls back before its working budget is exceeded", async (t) => {
  const prior = globalThis.File;
  globalThis.File = File;
  t.after(() => {
    globalThis.File = prior;
  });
  const original = new File(
    ["<gpx>synthetic</gpx>".repeat(10000)],
    "synthetic.gpx",
    { type: "application/gpx+xml" },
  );
  original.arrayBuffer = () => {
    throw new Error("whole original was buffered");
  };
  const result = await prepareFile(original, {
    chunkSize: 4096,
    maxWorking: 1024 * 1024,
    maxOriginal: 1024 * 1024,
  });
  assert.equal(result.clientWrapped, true);
  assert.equal(result.file.name, "synthetic.gpx.zip");
  assert.ok(result.file.size < original.size);
  const limited = await prepareFile(original, { maxOriginal: 10 });
  assert.equal(limited.file, original);
  assert.equal(limited.fallback, "size");
  const budget = await prepareFile(original, {
    maxWorking: 128,
    maxOriginal: 1024 * 1024,
    chunkSize: 32,
  });
  assert.equal(budget.file, original);
  assert.equal(budget.fallback, "compression");
});

test("cancelled target lookup aborts and a late response cannot start a PUT", async (t) => {
  const originals = {
    fetch: globalThis.fetch,
    document: globalThis.document,
    xhr: globalThis.XMLHttpRequest,
  };
  t.after(() => {
    globalThis.fetch = originals.fetch;
    globalThis.document = originals.document;
    globalThis.XMLHttpRequest = originals.xhr;
  });
  let release, cancel, stopped;
  const put = [],
    progress = [],
    errors = [];
  globalThis.document = {
    querySelector: () => ({
      content: "synthetic-csrf",
      getAttribute: () => "synthetic-csrf",
    }),
  };
  globalThis.fetch = (_url, opts) => {
    if (_url.endsWith("cancel")) return Promise.resolve({ ok: true });
    stopped = opts.signal;
    return new Promise((resolve) => {
      release = resolve;
    });
  };
  globalThis.XMLHttpRequest = class {
    constructor() {
      put.push(this);
      this.upload = { addEventListener() {} };
    }
    open() {}
    send() {}
    setRequestHeader() {}
    abort() {}
  };
  Direct(
    [
      {
        meta: { upload_ref: "owned-reference" },
        file: new Blob(["zip"]),
        onCancel: (fn) => {
          cancel = fn;
        },
        isCancelled: () => false,
        progress: (n) => progress.push(n),
        error: (error) => errors.push(error),
      },
    ],
    () => {},
  );
  await flush();
  assert.equal(typeof cancel, "function");
  cancel();
  assert.equal(stopped.aborted, true);
  release({
    ok: true,
    json: async () => ({ url: "transient-target", headers: {} }),
  });
  await flush();
  assert.deepEqual(put, []);
  assert.deepEqual(progress, []);
  assert.deepEqual(errors, []);
});

test("duplicate progress does not extend the upload inactivity deadline", async (t) => {
  const prior = {
    fetch: globalThis.fetch,
    document: globalThis.document,
    xhr: globalThis.XMLHttpRequest,
    setTimeout: globalThis.setTimeout,
    clearTimeout: globalThis.clearTimeout,
  };
  t.after(() => {
    for (const [key, value] of Object.entries(prior))
      globalThis[key === "xhr" ? "XMLHttpRequest" : key] = value;
  });
  const timers = [];
  let progress, cancel;
  globalThis.setTimeout = (fn) => {
    timers.push(fn);
    return timers.length;
  };
  globalThis.clearTimeout = () => {};
  globalThis.document = {
    querySelector: () => ({ getAttribute: () => "synthetic-csrf" }),
  };
  globalThis.fetch = async () => ({
    ok: true,
    json: async () => ({ url: "transient-target", headers: {} }),
  });
  globalThis.XMLHttpRequest = class {
    constructor() {
      this.upload = {
        addEventListener: (_event, fn) => {
          progress = fn;
        },
      };
    }
    open() {}
    setRequestHeader() {}
    send() {}
    abort() {}
  };
  Direct(
    [
      {
        meta: { upload_ref: "owned-reference" },
        file: "bytes",
        onCancel: (fn) => {
          cancel = fn;
        },
        isCancelled: () => false,
        progress() {},
        error() {},
      },
    ],
    () => {},
  );
  await flush();
  progress({ lengthComputable: true, loaded: 1, total: 5 });
  const afterProgress = timers.length;
  progress({ lengthComputable: true, loaded: 1, total: 5 });
  assert.equal(timers.length, afterProgress);
  cancel();
});
