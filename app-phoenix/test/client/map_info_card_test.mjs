import assert from "node:assert/strict"
import test from "node:test"
import { createInfoCard } from "../../assets/js/map/ui/info_card.js"

function fixture({ confirmed = true } = {}) {
  const node = () => ({
    innerHTML: "",
    textContent: "",
    classes: new Set(["hidden", "mt-4"]),
    get classList() {
      return {
        add: (name) => this.classes.add(name),
        remove: (name) => this.classes.delete(name),
        contains: (name) => this.classes.has(name),
      }
    },
  })
  const nodes = {
    "[data-native-info-display]": node(),
    "[data-native-info-title]": node(),
    "[data-native-info-content]": node(),
    "[data-native-info-actions]": node(),
  }
  const listeners = {}
  const pushes = []
  const confirms = []
  const frameLookup = (selector) =>
    selector === "#point-address-7" ? (nodes.frame ??= node()) : null
  nodes["[data-native-info-content]"].querySelector = frameLookup
  const labels = {
    "messages.edit": "Edit",
    "messages.delete": "Delete",
    "map_info.place": "Place",
    "map_info.area": "Area",
    "map_info.radius": "Radius",
    "map_info.center": "Center",
    "map_info.place_name_locked": "Name locked",
    "map_info.location_point": "Location Point",
    "map_info.coordinates": "Coordinates",
    "map_info.time": "Time",
    "map_info.battery": "Battery",
    "map_info.altitude": "Altitude",
    "map_info.speed": "Speed",
    "points.address.address": "Address:",
    "areas.confirm_delete_named": "Delete area {name}?",
    "map.confirm_delete_point_permanently": "Delete point?",
  }
  const card = createInfoCard({
    root: {
      querySelector: (selector) => nodes[selector],
      addEventListener: (name, fn) => {
        listeners[name] = fn
      },
      removeEventListener: () => {},
    },
    pushEvent: (event, payload, reply) => {
      pushes.push([event, payload])
      if (event === "address:open") reply?.({ text: "Main St 1 & Co" })
    },
    getConfig: () => ({
      uiLabels: labels,
      range: { timezone: "UTC" },
      distanceUnit: "km",
    }),
    confirm: (message) => {
      confirms.push(message)
      return confirmed
    },
    lifetime: { own() {} },
  })
  const click = (dataset) =>
    listeners.click({
      target: {
        closest: (selector) =>
          selector === "[data-native-info-display]"
            ? {}
            : selector === "[data-native-info-action]" && dataset.action
              ? { dataset }
              : selector === "[data-native-info-close]" && dataset.close
                ? {}
                : null,
      },
    })
  return { card, nodes, pushes, confirms, click }
}

test("a place click fills the Rails info card and opens the Tools tab", () => {
  const f = fixture()
  f.card.place({ id: 3, name: "Café & Bar", nameLocked: true })
  assert.equal(f.nodes["[data-native-info-title]"].textContent, "Café &amp; Bar")
  assert.match(
    f.nodes["[data-native-info-content]"].innerHTML,
    /data-testid="place-name-lock">Name locked</,
  )
  assert.equal(
    f.nodes["[data-native-info-actions]"].innerHTML,
    '<button class="btn btn-sm btn-primary" data-native-info-action="edit" data-id="3" data-entity-type="place">Edit</button>',
  )
  assert.equal(f.nodes["[data-native-info-display]"].classes.has("hidden"), false)
  assert.deepEqual(f.pushes, [["map:panel", { panel: "tools" }]])
  f.click({ action: "edit", id: "3", entityType: "place" })
  assert.deepEqual(f.pushes.at(-1), ["place:edit", { id: "3" }])
})

test("an area card offers Edit and a confirmed Delete", () => {
  const f = fixture()
  f.card.area({ id: 5, name: "Home", radius: 120.4, latitude: 52.5, longitude: 13.4 })
  const content = f.nodes["[data-native-info-content]"].innerHTML
  assert.match(content, /Radius:<\/span> 120m/)
  assert.match(content, /Center:<\/span> 52\.500000, 13\.400000/)
  assert.match(f.nodes["[data-native-info-actions]"].innerHTML, /btn btn-sm btn-error/)
  f.click({ action: "edit", id: "5", entityType: "area" })
  f.click({ action: "delete", id: "5", entityType: "area" })
  assert.deepEqual(f.confirms, ["Delete area Home?"])
  assert.deepEqual(f.pushes.slice(-2), [
    ["area:edit", { id: "5" }],
    ["area:delete", { id: "5" }],
  ])
  const refused = fixture({ confirmed: false })
  refused.card.area({ id: 5, name: "Home" })
  refused.click({ action: "delete", id: "5", entityType: "area" })
  assert.equal(refused.pushes.some(([event]) => event === "area:delete"), false)
})

test("a point card loads the address into the Rails frame and deletes after confirm", () => {
  const f = fixture()
  f.card.point(
    { id: 7, timestamp: 1700000000, battery: 80, altitude: 34.6, velocity: 10, latitude: "52.1", longitude: "13.2" },
    { coordinates: [0, 0] },
  )
  const content = f.nodes["[data-native-info-content]"].innerHTML
  assert.match(content, /<turbo-frame id="point-address-7"><\/turbo-frame>/)
  assert.match(content, /Coordinates:<\/span> 52\.100000, 13\.200000/)
  assert.match(content, /Battery:<\/span> 80%/)
  assert.match(content, /Altitude:<\/span> 35m/)
  assert.match(content, /Speed:<\/span> 36 km\/h/)
  assert.deepEqual(f.pushes.at(-1), ["address:open", { id: 7 }])
  assert.equal(
    f.nodes.frame.innerHTML,
    '<div><span class="font-semibold">Address:</span> Main St 1 &amp; Co</div>',
  )
  f.click({ action: "delete", id: "7", entityType: "point" })
  assert.deepEqual(f.confirms, ["Delete point?"])
  assert.deepEqual(f.pushes.at(-1), ["point:delete", { point_id: "7" }])
})

test("the close button hides the card", () => {
  const f = fixture()
  f.card.show("Title", "<p>x</p>")
  f.click({ close: true })
  assert.equal(f.nodes["[data-native-info-display]"].classes.has("hidden"), true)
})

test("a card node replaced by a patch still fills and routes its actions", () => {
  const f = fixture()
  const fresh = {}
  for (const name of ["display", "title", "content", "actions"]) {
    const old = f.nodes[`[data-native-info-${name}]`]
    fresh[name] = { ...old, innerHTML: "", textContent: "", classes: new Set(["hidden"]) }
    Object.defineProperty(fresh[name], "classList", Object.getOwnPropertyDescriptor(old, "classList"))
    f.nodes[`[data-native-info-${name}]`] = fresh[name]
  }
  f.card.place({ id: 4, name: "Moved" })
  assert.equal(fresh.title.textContent, "Moved")
  assert.equal(fresh.display.classes.has("hidden"), false)
  f.click({ action: "edit", id: "4", entityType: "place" })
  assert.deepEqual(f.pushes.at(-1), ["place:edit", { id: "4" }])
})

