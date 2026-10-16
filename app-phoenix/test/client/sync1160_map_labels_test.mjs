import assert from "node:assert/strict";
import test from "node:test";
import { VisitsLayer } from "../../assets/js/map/layers/visits.js";
import { AreasLayer } from "../../assets/js/map/layers/areas.js";
import { createFamilyOverlay } from "../../assets/js/map/family/overlay.js";
import { installHostShortcuts } from "../../assets/js/map/ui/shortcuts.js";

function fixture() {
  const markers = new Set(),
    layers = new Map(),
    sources = new Map(),
    events = new Map();
  let features = [];
  const document = { createElement: () => ({ style: {}, textContent: "" }) };
  const map = {
    getContainer: () => ({ ownerDocument: document }),
    getLayer: (id) => layers.get(id),
    getSource: (id) => sources.get(id),
    addLayer: (layer) => layers.set(layer.id, layer),
    removeLayer: (id) => layers.delete(id),
    addSource(id, source) {
      sources.set(id, {
        ...source,
        setData(data) {
          this.data = data;
        },
      });
    },
    removeSource: (id) => sources.delete(id),
    setFilter(id, filter) {
      layers.get(id).filter = filter;
    },
    setLayoutProperty(id, key, value) {
      (layers.get(id).layout ??= {})[key] = value;
    },
    getLayoutProperty: (id, key) => layers.get(id)?.layout?.[key],
    queryRenderedFeatures: () => features,
    on(event, id, fn) {
      const key = fn ? `${event}:${id}` : event;
      if (!events.has(key)) events.set(key, new Set());
      events.get(key).add(fn ?? id);
    },
    off(event, id, fn) {
      events.get(fn ? `${event}:${id}` : event)?.delete(fn ?? id);
    },
  };
  class Marker {
    constructor({ element }) {
      this.element = element;
    }
    setLngLat(at) {
      this.at = at;
      return this;
    }
    addTo() {
      markers.add(this);
      return this;
    }
    getElement() {
      return this.element;
    }
    remove() {
      markers.delete(this);
    }
  }
  const emit = (name) => {
    for (const f of events.get(name) ?? []) f();
  };
  return {
    map,
    markers,
    layers,
    sources,
    events,
    library: { Marker },
    emit,
    rows(value) {
      features = value;
    },
  };
}
const point = (id, name) => ({
  properties: { id, name },
  geometry: { type: "Point", coordinates: [13, 52] },
});

test("Unicode visit labels use safe DOM text and follow visibility status dimming style refresh and teardown", () => {
  const f = fixture(),
    visits = new VisitsLayer(f.map, { library: f.library });
  const row = point(1, "🏖️ <img src=x onerror=alert(1)>");
  f.rows([row]);
  visits.add({ type: "FeatureCollection", features: [row] });
  f.emit("render");
  assert.equal(f.markers.size, 1);
  const label = [...f.markers][0].getElement();
  assert.equal(label.textContent, row.properties.name);
  assert.equal(label.style.pointerEvents, "none");
  assert.equal(f.layers.get("visits-labels"), undefined);
  visits.setLabelOpacity((properties) => (properties.id === 1 ? 0.15 : 1));
  f.emit("render");
  assert.equal(label.style.opacity, "0.15");
  visits.hide();
  assert.equal(f.markers.size, 0);
  visits.show();
  f.emit("render");
  assert.equal(f.markers.size, 1);
  f.rows([]);
  visits.setStatusFilter({ confirmed: false });
  f.emit("render");
  assert.equal(f.markers.size, 0);
  f.rows([row]);
  f.layers.clear();
  f.sources.clear();
  visits.add(visits.data);
  f.emit("render");
  f.emit("render");
  assert.equal(f.markers.size, 1);
  visits.remove();
  assert.equal(f.markers.size, 0);
  assert.equal(f.events.get("render").size, 0);
});

test("Unicode area labels remain at area center without vector font fallback or duplicate markers", () => {
  const f = fixture(),
    areas = new AreasLayer(f.map, { library: f.library });
  const row = {
    properties: {
      id: 2,
      name: "🏡 家 & <b>Home</b>",
      latitude: 52,
      longitude: 13,
    },
    geometry: {
      type: "Polygon",
      coordinates: [
        [
          [12, 51],
          [14, 51],
          [14, 53],
          [12, 53],
          [12, 51],
        ],
      ],
    },
  };
  f.rows([row, row]);
  areas.add({ type: "FeatureCollection", features: [row] });
  f.emit("render");
  assert.equal(f.markers.size, 1);
  assert.deepEqual([...f.markers][0].at, [13, 52]);
  assert.equal([...f.markers][0].element.textContent, row.properties.name);
  areas.remove();
  assert.equal(f.markers.size, 0);
});

test("family Unicode names and current rows restore once after style replacement and clean listeners", () => {
  const f = fixture(),
    intervals = new Set();
  const timers = {
    setInterval(fn) {
      intervals.add(fn);
      return fn;
    },
    clearInterval(fn) {
      intervals.delete(fn);
    },
  };
  let popupHtml = "";
  f.library.Popup = class {
    setLngLat() {
      return this;
    }
    setHTML(html) {
      popupHtml = html;
      return this;
    }
    addTo() {
      return this;
    }
    remove() {}
  };
  const overlay = createFamilyOverlay({ ...f, timers });
  const row = {
    user_id: 3,
    name: "👨‍👩‍👧 Ada <script>",
    address: "<img src=x> Street & City",
    email: "fallback",
    latitude: 52,
    longitude: 13,
    timestamp: 1,
  };
  f.rows([point(3, row.name)]);
  overlay.replace([row]);
  const select = () => {
    for (const handler of f.events.get("click:family-circles"))
      handler({ features: [{ properties: { id: 3 } }] });
  };
  select();
  assert.match(popupHtml, /&lt;img src=x&gt; Street &amp; City/);
  assert.equal(popupHtml.includes("<img"), false);
  overlay.replace([{ ...row, address: null }]);
  select();
  assert.equal(popupHtml.includes("Street"), false);
  assert.equal(popupHtml.includes("null"), false);
  overlay.replace([row]);

  f.emit("render");
  assert.equal(f.markers.size, 1);
  assert.equal([...f.markers][0].element.textContent, row.name);
  f.layers.clear();
  f.sources.clear();
  f.emit("style.load");
  f.emit("style.load");
  f.emit("render");
  assert.equal(
    f.sources.get("family-members").data.features[0].properties.name,
    row.name,
  );
  assert.equal(f.markers.size, 1);
  overlay.clear();
  f.rows([]);
  f.emit("render");
  assert.equal(f.markers.size, 0);
  overlay.destroy();
  assert.equal(intervals.size, 0);
  assert.equal(f.events.get("style.load").size, 0);
});

test("F and C shortcuts use admitted Family and Tools buttons and release document handlers", () => {
  let keydown,
    disposed,
    clicks = [];
  const buttons = new Map([
    ["family", { click: () => clicks.push("family") }],
    ["tools", { click: () => clicks.push("tools") }],
  ]);
  const root = {
    ownerDocument: {
      addEventListener(_n, f) {
        keydown = f;
      },
      removeEventListener(_n, f) {
        assert.equal(f, keydown);
        disposed = true;
      },
    },
    querySelector(selector) {
      return buttons.get(selector.match(/map-button-(\w+)/)?.[1]);
    },
  };
  installHostShortcuts({
    root,
    lifetime: {
      own(fn) {
        this.dispose = fn;
        disposed = fn;
      },
    },
  });
  const event = (key) => ({
    key,
    target: { closest: () => null },
    preventDefault() {},
  });
  keydown(event("F"));
  keydown(event("c"));
  assert.deepEqual(clicks, ["family", "tools"]);
  buttons.delete("family");
  keydown(event("f"));
  assert.equal(clicks.length, 2);
  keydown({ ...event("c"), target: { closest: () => ({}) } });
  assert.equal(clicks.length, 2);
  disposed();
  assert.equal(disposed, true);
});

test("anomaly preference survives document reload and Points visibility without borrowing another user preference", async () => {
  const { fixture: host } = await import(
    "../../../spec/javascript/support/native_m6_host_fixture.mjs"
  );
  const previous = Object.getOwnPropertyDescriptor(globalThis, "localStorage");
  const stored = new Map();
  Object.defineProperty(globalThis, "localStorage", {
    configurable: true,
    value: {
      getItem: (k) => stored.get(k) ?? null,
      setItem: (k, v) => stored.set(k, v),
    },
  });
  const f = host({
    namespace: "user:synthetic",
    pointsEnabled: true,
    anomaliesEnabled: false,
  });
  let second, foreign;
  try {
    await f.owner.mount();
    await f.owner.update({
      ...f.owner.config,
      anomaliesPreferred: true,
      anomaliesEnabled: true,
    });
    f.owner.destroy();
    second = host({
      namespace: "user:synthetic",
      pointsEnabled: false,
      anomaliesEnabled: false,
    });
    await second.owner.mount();
    assert.equal(second.owner.config.anomaliesPreferred, true);
    assert.equal(second.owner.config.anomaliesEnabled, false);
    await second.owner.update({ ...second.owner.config, pointsEnabled: true });
    assert.equal(second.owner.config.anomaliesEnabled, true);
    assert.equal(
      second.pushed.some(
        (x) => x.event === "map:anomalies" && x.payload.enabled === "true",
      ),
      true,
    );
    foreign = host({
      namespace: "user:other",
      pointsEnabled: true,
      anomaliesEnabled: false,
    });
    assert.equal(foreign.owner.config.anomaliesEnabled, false);
  } finally {
    f.owner.destroy();
    second?.owner.destroy();
    foreign?.owner.destroy();
    if (previous) Object.defineProperty(globalThis, "localStorage", previous);
    else delete globalThis.localStorage;
  }
});
