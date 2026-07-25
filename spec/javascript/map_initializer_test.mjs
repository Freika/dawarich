import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

async function loadMapInitializer({ getMapStyle, Toast }) {
  const source = await readFile(
    new URL(
      "../../app/javascript/controllers/maps/maplibre/map_initializer.js",
      import.meta.url,
    ),
    "utf8",
  );
  const withoutImports = source.replace(
    /^import[\s\S]*?from "[^"]+";?\n/gm,
    "",
  );
  const dependencies = `
    const maplibregl = globalThis.__mapInitializerMaplibre
    const getMapStyle = globalThis.__mapInitializerGetMapStyle
    const Toast = globalThis.__mapInitializerToast
  `;
  globalThis.__mapInitializerGetMapStyle = getMapStyle;
  globalThis.__mapInitializerToast = Toast;
  const url = `data:text/javascript;base64,${Buffer.from(`${dependencies}\n${withoutImports}`).toString("base64")}`;
  return await import(`${url}#${Date.now()}`);
}

class FakeMap {
  constructor(options) {
    this.options = options;
    this.listeners = new Map();
    this.setStyles = [];
  }

  once(event, callback) {
    this.listeners.set(event, callback);
  }

  off(event, callback) {
    if (this.listeners.get(event) === callback) this.listeners.delete(event);
  }

  emit(event) {
    const callback = this.listeners.get(event);
    this.listeners.delete(event);
    callback?.();
  }

  setStyle(style) {
    this.setStyles.push(style);
  }

  addControl() {}
}

test("falls back from an unavailable initial custom style URL", async () => {
  let map;
  const errors = [];
  globalThis.__mapInitializerMaplibre = {
    Map: class extends FakeMap {
      constructor(options) {
        super(options)
        map = this
        queueMicrotask(() => this.emit("error"))
      }
    },
    NavigationControl: class {},
    AttributionControl: class {},
  };
  const fallback = { version: 8, sources: {}, layers: [] };
  const { MapInitializer } = await loadMapInitializer({
    getMapStyle: async (_styleName, options) =>
      options.vectorTilesUrl
        ? "https://tiles.example/broken-style.json"
        : fallback,
    Toast: { error: (message) => errors.push(message) },
  });

  await MapInitializer.initialize(
    {},
    { vectorTilesUrl: "https://tiles.example/broken-style.json" },
  );
  await new Promise((resolve) => setImmediate(resolve));

  assert.deepEqual(map.setStyles, [fallback]);
  assert.equal(errors.length, 1);
});
