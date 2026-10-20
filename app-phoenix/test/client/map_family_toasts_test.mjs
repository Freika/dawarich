import assert from "node:assert/strict";
import test from "node:test";
import { setImmediate } from "node:timers/promises";
import { createMapFamilyLayer } from "../../assets/js/map/family/host.js";
import { Toast } from "../../assets/js/map/ui/toast.js";
import { miniDocument } from "./support/mini_dom.mjs";

function fixture(t) {
  const notices = [],
    flights = [];
  const document = miniDocument();
  document.body = document.createElement("body");
  const root = document.createElement("main");
  root.ownerDocument = document;
  const list = document.createElement("div");
  list.isConnected = true;
  const group = document.createElement("div");
  root.querySelector = (selector) =>
    ({
      "#native-family-members": list,
      "#native-family-list": group,
    })[selector];
  t.mock.getter(globalThis, "document", () => document);
  for (const type of ["info", "success", "error"])
    t.mock.method(Toast, type, (message) => notices.push([type, message]));
  const location = { user_id: 7, name: "Member", longitude: 13, latitude: 52 };
  const reader = {
    async read(resource) {
      return {
        data:
          resource === "family_locations"
            ? { locations: [location] }
            : { members: [] },
      };
    },
  };
  const owner = createMapFamilyLayer({
    map: { flyTo: (options) => flights.push(options) },
    reader,
    root,
    createOverlay: () => ({ replace() {}, clear() {}, destroy() {} }),
  });
  t.after(() => owner.destroy());
  const config = {
    familyEnabled: true,
    locale: "en",
    range: { startAt: "2026-06-01", endAt: "2026-06-02" },
    uiLabels: {
      "messages.family_feature_not_available": "Family feature not available",
      "family.loaded_members": "Loaded {count} family members",
      "family.loaded_members.one": "Loaded 1 family member",
      "messages.failed_to_load_family_members": "Failed to load family members",
      "messages.centered_on_family_member": "Centered on family member",
    },
  };
  return { owner, reader, config, notices, flights, list, location };
}

if (!("document" in globalThis))
  Object.defineProperty(globalThis, "document", {
    configurable: true,
    get: () => undefined,
  });

test("Family locations 403 shows Rails feature unavailable info toast", async (t) => {
  const f = fixture(t);
  f.reader.read = async () => {
    throw Object.assign(new Error("Unavailable"), { status: 403 });
  };
  await f.owner.update({ ...f.config, familyEnabled: false });
  await setImmediate();
  assert.deepEqual(f.notices, []);
  await f.owner.update(f.config);
  await setImmediate();
  assert.deepEqual(f.notices, [["info", "Family feature not available"]]);
});

test("Family locations success toasts Rails member count before independent history", async (t) => {
  const f = fixture(t);
  for (const count of [0, 1, 2]) {
    let rejectHistory;
    const history = new Promise((_, reject) => {
      rejectHistory = reject;
    });
    f.reader.read = async (resource) =>
      resource === "family_locations"
        ? {
            data: {
              locations: Array.from({ length: count }, (_, i) => ({
                ...f.location,
                user_id: i + 1,
              })),
            },
          }
        : history;
    const loading = f.owner.update(f.config);
    await setImmediate();
    assert.deepEqual(f.notices.at(-1), [
      "success",
      `Loaded ${count} family member${count === 1 ? "" : "s"}`,
    ]);
    rejectHistory(
      Object.assign(new Error("History unavailable"), { status: 403 }),
    );
    await loading;
    await setImmediate();
    assert.equal(f.notices.length, count + 1);
    assert.equal(f.list.children.length, count || 1);
  }
});

test("Family locations failure shows Rails error toast and cancellation stays silent", async (t) => {
  const f = fixture(t);
  for (const status of [401, 500, undefined]) {
    f.reader.read = async () => {
      throw Object.assign(new Error("Read failed"), { status });
    };
    await f.owner.update(f.config);
    await setImmediate();
    assert.deepEqual(f.notices.at(-1), [
      "error",
      "Failed to load family members",
    ]);
  }
  assert.equal(f.notices.length, 3);
  f.reader.read = () => new Promise(() => {});
  const controller = new AbortController();
  const loading = f.owner.update(f.config, { signal: controller.signal });
  controller.abort();
  await loading;
  await setImmediate();
  assert.equal(f.notices.length, 3);
  const superseded = f.owner.update(f.config);
  await f.owner.update({ ...f.config, familyEnabled: false });
  await superseded;
  await setImmediate();
  assert.equal(f.notices.length, 3);
});

test("Family member click and keyboard centering show Rails success toast only while admitted", async (t) => {
  const f = fixture(t);
  await f.owner.update(f.config);
  await setImmediate();
  f.notices.length = 0;
  const row = f.list.children[0];
  row.click();
  for (const key of ["Enter", " "]) row.dispatch("keydown", { key });
  await setImmediate();
  assert.deepEqual(
    f.notices,
    Array(3).fill(["success", "Centered on family member"]),
  );
  assert.deepEqual(
    f.flights,
    Array(3).fill({ center: [13, 52], zoom: 15, duration: 1500 }),
  );
  f.list.isConnected = false;
  row.click();
  f.list.isConnected = true;
  await f.owner.update({ ...f.config, familyEnabled: false });
  row.click();
  f.owner.destroy();
  row.click();
  await setImmediate();
  assert.equal(f.notices.length, 3);
  assert.equal(f.flights.length, 3);
});
