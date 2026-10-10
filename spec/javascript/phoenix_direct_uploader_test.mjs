import assert from "node:assert/strict";
import test from "node:test";

const { Direct } = await import(
  "../../app-phoenix/assets/js/uploaders/direct.js"
);

function fakeXhr(t, status) {
  const sent = [];
  class FakeXhr {
    constructor() {
      this.headers = {};
      this.upload = {
        listeners: {},
        addEventListener: (name, fn) => {
          this.upload.listeners[name] = fn;
        },
      };
      sent.push(this);
    }
    open(method, url) {
      this.method = method;
      this.url = url;
    }
    setRequestHeader(key, value) {
      this.headers[key] = value;
    }
    send(body) {
      this.body = body;
      this.upload.listeners.progress?.({
        lengthComputable: true,
        loaded: 5,
        total: 10,
      });
      this.status = status;
      this.onload();
    }
    abort() {
      this.aborted = true;
    }
  }
  const originalFetch = globalThis.fetch;
  const originalDocument = globalThis.document;
  globalThis.document = {
    querySelector: () => ({ getAttribute: () => "synthetic-csrf" }),
  };
  globalThis.fetch = async () => ({
    ok: true,
    json: async () => ({
      url: "http://www.example.com/rails/active_storage/disk/token",
      headers: { "Content-Type": "application/zip" },
    }),
  });
  const original = globalThis.XMLHttpRequest;
  globalThis.XMLHttpRequest = FakeXhr;
  t.after(() => {
    globalThis.XMLHttpRequest = original;
    globalThis.fetch = originalFetch;
    globalThis.document = originalDocument;
  });
  return sent;
}

function entry() {
  const calls = { progress: [], errors: 0 };
  return {
    calls,
    file: "archive-bytes",
    meta: { upload_ref: "synthetic-owned-reference" },
    onCancel: () => {},
    progress: (percent) => calls.progress.push(percent),
    error: () => {
      calls.errors += 1;
    },
  };
}

test("the direct uploader PUTs the file with the presigned headers and reports progress", async (t) => {
  const sent = fakeXhr(t, 204);
  const upload = entry();

  Direct([upload], () => {});
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(sent.length, 1);
  assert.equal(sent[0].method, "PUT");
  assert.equal(
    sent[0].url,
    "http://www.example.com/rails/active_storage/disk/token",
  );
  assert.deepEqual(sent[0].headers, { "Content-Type": "application/zip" });
  assert.equal(sent[0].body, "archive-bytes");
  assert.deepEqual(upload.calls.progress, [50, 100]);
  assert.equal(upload.calls.errors, 0);
});

test("the direct uploader reports an error when storage refuses the file", async (t) => {
  fakeXhr(t, 422);
  const upload = entry();

  Direct([upload], () => {});
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(upload.calls.errors, 1);
  assert.deepEqual(upload.calls.progress, [50]);
});

test("disconnect cancels a completed pending PUT through the owned HTTP endpoint", async (t) => {
  fakeXhr(t, 204);
  const requests = [];
  const target = globalThis.fetch;
  globalThis.fetch = (...args) => {
    requests.push(args);
    return target(...args);
  };
  const upload = entry();
  let disconnect;
  Direct([upload], (callback) => { disconnect = callback; });
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(upload.calls.progress, [50, 100]);
  disconnect();
  disconnect();
  const cancelled = requests.filter(([url]) => url === "/native/uploads/cancel");
  assert.equal(cancelled.length, 1);
  assert.deepEqual(JSON.parse(cancelled[0][1].body), {upload_ref: upload.meta.upload_ref});
  assert.equal(cancelled[0][1].cache, "no-store");
  assert.equal(cancelled[0][1].keepalive, true);
});
