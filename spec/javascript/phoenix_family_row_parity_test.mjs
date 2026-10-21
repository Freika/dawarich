import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { createMapFamilyLayer } from "../../app-phoenix/assets/js/map/family/host.js";

const fixture = JSON.parse(
  readFileSync(
    new URL(
      "../../app-phoenix/test/fixtures/map_ui/rails-1.16.0-family-rows.json",
      import.meta.url,
    ),
  ),
);
class Element {
  constructor(tag = "div") {
    Object.assign(this, {
      tag,
      className: "",
      dataset: {},
      style: {},
      children: [],
      textContent: "",
      listeners: {},
      isConnected: true,
    });
  }
  append(...children) {
    this.children.push(...children);
  }
  replaceChildren(...children) {
    this.children = children;
  }
  setAttribute(key, value) {
    if (key === "class") this.className = value;
    else if (key.startsWith("data-"))
      this.dataset[
        key.slice(5).replace(/-([a-z])/g, (_, char) => char.toUpperCase())
      ] = value;
    else this[key] = value;
  }
  addEventListener(key, handler) {
    this.listeners[key] = handler;
  }
}
function shape({
  tag,
  className,
  dataset,
  style,
  children,
  textContent,
  title,
}) {
  const { familyMemberId, familySharingSince, ...visible } = dataset;
  return {
    tag,
    className,
    dataset: visible,
    style,
    children: children.map(shape),
    textContent,
    ...(title ? { title } : {}),
  };
}
function mount(rows) {
  const list = new Element(),
    wrapper = new Element(),
    status = new Element();
  const flights = [];
  const owner = createMapFamilyLayer({
    root: {
      querySelector: (selector) =>
        ({
          "#native-family-members": list,
          "#native-family-list": wrapper,
          "#native-family-status": status,
        })[selector],
      ownerDocument: { createElement: (tag) => new Element(tag) },
    },
    map: { flyTo: (options) => flights.push(options) },
    reader: { read: async () => ({ data: { locations: rows } }) },
    createOverlay: () => ({ clear() {}, replace() {}, destroy() {} }),
  });
  const update = () =>
    owner.update({
      familyEnabled: true,
      locale: "en",
      range: { timezone: "Europe/Berlin" },
      uiLabels: {
        "common.unknown": "Unknown",
        "family.none_sharing": "No family members sharing location",
      },
    });
  return { owner, list, wrapper, flights, update };
}
test("runtime Family member rows match the Rails 1.16.0 renderer including escaped text and empty info lines", async () => {
  const f = mount(fixture.rows);
  try {
    await f.update();
    assert.deepEqual(f.list.children.map(shape), fixture.expected);
    f.list.children[0].listeners.click();
    assert.deepEqual(f.flights[0], {
      center: [13.5, 52.4],
      zoom: 15,
      duration: 1500,
    });
    const row = f.list.children[0];
    assert.equal(row.role, "button");
    assert.equal(row.tabindex, "0");
    row.listeners.keydown({ key: "Enter", preventDefault() {} });
    assert.equal(f.flights.length, 2);
  } finally {
    f.owner.destroy();
  }
});
test("runtime Family empty state uses the Rails paragraph inside the visible member list", async () => {
  const f = mount([]);
  try {
    await f.update();
    assert.equal(f.wrapper.style.display, "block");
    assert.equal(
      `<p class="${f.list.children[0].className}">${f.list.children[0].textContent}</p>`,
      fixture.emptyHtml,
    );
    assert.deepEqual(f.list.children.map(shape), [
      {
        tag: "p",
        className: "text-xs text-base-content/60",
        dataset: {},
        style: {},
        children: [],
        textContent: "No family members sharing location",
      },
    ]);
  } finally {
    f.owner.destroy();
  }
});
