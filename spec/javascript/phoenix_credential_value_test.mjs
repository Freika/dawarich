import assert from "node:assert/strict";
import test from "node:test";
import { CredentialValue } from "../../app-phoenix/assets/js/hooks/credential_value.js";

test("account key reveals clear on patch disconnect and destroy while stale responses cannot refill the DOM", async (t) => {
  const prior = {
    fetch: globalThis.fetch,
    document: globalThis.document,
    window: globalThis.window,
  };
  t.after(() => {
    Object.assign(globalThis, prior);
  });
  const pending = [],
    listeners = new Map();
  globalThis.window = {
    addEventListener: (event, fn) => listeners.set(event, fn),
    removeEventListener: (event) => listeners.delete(event),
  };
  globalThis.document = {
    querySelector: () => ({ content: "synthetic-csrf" }),
  };
  globalThis.fetch = (_url, opts) =>
    new Promise((resolve) => pending.push({ opts, resolve }));
  const hook = Object.assign(Object.create(CredentialValue), {
    el: { textContent: "", dataset: {}, isConnected: true },
    handleEvent() {},
  });
  hook.mounted();
  pending
    .at(-1)
    .resolve({
      ok: true,
      json: async () => ({ api_key: "synthetic-private-key" }),
    });
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(hook.el.textContent, "synthetic-private-key");
  listeners.get("phx:page-loading-start")();
  assert.equal(hook.el.textContent, "");
  const request = hook.reveal();
  const target = pending.at(-1);
  hook.disconnected();
  assert.equal(target.opts.signal.aborted, true);
  target.resolve({
    ok: true,
    json: async () => ({ api_key: "stale-private-key" }),
  });
  await request;
  assert.equal(hook.el.textContent, "");
  const next = hook.reveal();
  const last = pending.at(-1);
  hook.destroyed();
  assert.equal(last.opts.signal.aborted, true);
  last.resolve({
    ok: true,
    json: async () => ({ api_key: "stale-after-destroy" }),
  });
  await next;
  assert.equal(hook.el.textContent, "");
  assert.equal(listeners.size, 0);
});
