import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

async function loadClass(path, dependencies, exportName) {
  const source = await readFile(new URL(path, import.meta.url), "utf8")
  const colorSource = await readFile(
    new URL(
      "../../app/javascript/maps_maplibre/utils/family_member_color.js",
      import.meta.url,
    ),
    "utf8",
  )
  const withoutImports = source.replace(/^import .*\n/gm, "")
  const url = `data:text/javascript;base64,${Buffer.from(`${colorSource.replace("export function", "function")}\n${dependencies}\n${withoutImports}`).toString("base64")}`
  const module = await import(url)
  return exportName ? module[exportName] : module.default
}

class Element {
  constructor() {
    this.style = {}
    this.dataset = {}
    this.children = []
  }

  append(...children) {
    this.children.push(...children)
  }

  replaceChildren(...children) {
    this.children = children
  }

  querySelector() {
    return null
  }
}

const originalDocument = globalThis.document
globalThis.document = {
  documentElement: { lang: "en" },
  createElement: () => new Element(),
}

const FamilyLayer = await loadClass(
  "../../app/javascript/maps_maplibre/layers/family_layer.js",
  `const translate = (key) => key
   const escapeHtml = (value) => value
   const maplibregl = { Popup: class {} }
   class BaseLayer {
     constructor(map, options) { this.map = map; this.id = options.id; this.sourceId = "family-source" }
     update(data) { this.data = data }
   }`,
  "FamilyLayer",
)
const MapController = await loadClass(
  "../../app/javascript/controllers/maps/maplibre_controller.js",
  `class Controller {}
   const translate = (key) => key`,
)

const expectedColors = new Map([
  [2, "#f59e0b"],
  [3, "#ef4444"],
  [4, "#8b5cf6"],
])
const locations = [2, 3, 4].map((user_id) => ({
  user_id,
  email: `member-${user_id}@example.test`,
  longitude: 13.4 + user_id / 100,
  latitude: 52.5,
  updated_at: "2026-09-26T12:00:00Z",
  color: "#000000",
}))

test("family marker, history line and list color follow member ID across location orders and realtime updates", async (t) => {
  t.after(() => {
    globalThis.document = originalDocument
  })

  for (const orderedLocations of [locations, [...locations].reverse()]) {
    let historyData
    const map = {
      getSource: () => ({
        setData: (data) => {
          historyData = data
        },
      }),
    }
    const layer = new FamilyLayer(map)
    const controller = new MapController()
    const list = new Element()
    controller.hasFamilyMembersContainerTarget = true
    controller.familyMembersContainerTarget = list
    controller.timezoneValue = "UTC"
    controller.startDateValue = "2026-09-26T00:00:00Z"
    controller.endDateValue = "2026-09-26T23:59:59Z"
    controller.layerManager = { getLayer: () => layer }

    layer.loadMembers(orderedLocations)
    controller.renderFamilyMembersList(orderedLocations)
    const history = orderedLocations.map(({ user_id }) => ({
      user_id,
      points: [
        [52.5, 13.4],
        [52.6, 13.5],
      ],
      color: "#000000",
    }))
    const originalFetch = globalThis.fetch
    globalThis.fetch = async () => ({
      ok: true,
      json: async () => ({ members: history }),
    })
    try {
      await controller.loadFamilyHistory()
    } finally {
      globalThis.fetch = originalFetch
    }

    for (const { user_id } of orderedLocations) {
      const marker = layer.data.features.find(
        (feature) => feature.properties.id === user_id,
      )
      const line = historyData.features.find(
        (feature) => feature.properties.userId === user_id,
      )
      const row = list.children.find(
        (element) => element.dataset.memberId === user_id,
      )
      assert.equal(
        marker.properties.color,
        expectedColors.get(user_id),
        `marker ${user_id}`,
      )
      assert.equal(
        line.properties.color,
        expectedColors.get(user_id),
        `history ${user_id}`,
      )
      assert.equal(
        row.children[0].style.backgroundColor,
        expectedColors.get(user_id),
        `list ${user_id}`,
      )
    }

    const moved = { ...orderedLocations[0], longitude: 13.8 }
    layer.updateMember(moved)
    const marker = layer.data.features.find(
      (feature) => feature.properties.id === moved.user_id,
    )
    assert.equal(
      marker.properties.color,
      expectedColors.get(moved.user_id),
      `realtime ${moved.user_id}`,
    )
  }
})
