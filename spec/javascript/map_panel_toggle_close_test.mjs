import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/controllers/map_panel_controller.js",
    import.meta.url,
  ),
  "utf8",
)
const withoutImports = source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const dependencies = `
  class Controller {}
  const translate = (key) => key
`
const moduleUrl = `data:text/javascript;base64,${Buffer.from(
  `${dependencies}\n${withoutImports}`,
).toString("base64")}`
const { default: MapPanelController } = await import(moduleUrl)

// Minimal stand-ins for the pieces of the DOM and Stimulus that openTab reads.
function buildEnvironment({ open, activeTab, stubMarkActive = true }) {
  const classes = (initial) => {
    const set = new Set(initial)
    return {
      contains: (name) => set.has(name),
      add: (name) => set.add(name),
      remove: (name) => set.delete(name),
      toggle: (name, force) => (force ? set.add(name) : set.delete(name)),
    }
  }

  const tabContents = ["search", "layers", "settings"].map((tab) => ({
    dataset: { tabContent: tab },
    classList: classes(tab === activeTab ? ["active"] : []),
  }))

  const panel = {
    classList: classes(open ? ["open"] : []),
    querySelector: (selector) =>
      selector === "[data-tab-content].active"
        ? (tabContents.find((content) =>
            content.classList.contains("active"),
          ) ?? null)
        : null,
  }

  const mapContainer = {}
  const calls = { toggleSettings: 0, clusterCleared: 0 }
  const makeButton = (tab) => ({
    dataset: tab ? { tab } : {},
    classList: classes([]),
    attributes: {},
    setAttribute(name, value) {
      this.attributes[name] = value
    },
  })
  // The Replay and Poster buttons share the cluster class but carry no
  // data-tab, because they don't drive the panel.
  const nonPanelButton = makeButton(null)
  const clusterButtons = [makeButton("settings"), makeButton("layers")]

  globalThis.document = {
    querySelector: (selector) =>
      selector === ".map-control-panel" ? panel : null,
    getElementById: (id) =>
      id === "maps-maplibre-container" ? mapContainer : null,
    querySelectorAll: (selector) =>
      selector.includes("[data-tab]")
        ? clusterButtons
        : [...clusterButtons, nonPanelButton],
    addEventListener() {},
    removeEventListener() {},
    dispatchEvent() {},
  }

  const controller = new MapPanelController()
  controller.application = {
    getControllerForElementAndIdentifier: (element, identifier) => {
      if (element === mapContainer && identifier === "maps--maplibre") {
        return {
          toggleSettings() {
            calls.toggleSettings += 1
            panel.classList.toggle("open", !panel.classList.contains("open"))
          },
        }
      }
      if (element === panel && identifier === "map-panel") {
        return {
          switchToTab: (tab) => {
            calls.switchedTo = tab
          },
        }
      }
      return null
    },
  }
  if (stubMarkActive) {
    controller.markActiveClusterButton = (tab) => {
      calls.markedActive = tab
      if (tab === null) calls.clusterCleared += 1
    }
  }

  return { controller, panel, calls, clusterButtons, nonPanelButton }
}

function clickOn(tab) {
  return { currentTarget: { dataset: { tab } } }
}

test("clicking the button of the tab already on screen closes the panel", () => {
  const { controller, panel, calls } = buildEnvironment({
    open: true,
    activeTab: "settings",
  })

  controller.openTab(clickOn("settings"))

  assert.equal(panel.classList.contains("open"), false)
  assert.equal(calls.toggleSettings, 1)
  assert.equal(calls.clusterCleared, 1)
})

test("clicking a different tab switches instead of closing", () => {
  const { controller, panel, calls } = buildEnvironment({
    open: true,
    activeTab: "settings",
  })

  controller.openTab(clickOn("layers"))

  assert.equal(panel.classList.contains("open"), true)
  assert.equal(calls.toggleSettings, 0)
  assert.equal(calls.switchedTo, "layers")
})

test("clicking a tab while the panel is closed opens it", () => {
  const { controller, panel, calls } = buildEnvironment({
    open: false,
    activeTab: "settings",
  })

  controller.openTab(clickOn("settings"))

  assert.equal(panel.classList.contains("open"), true)
  assert.equal(calls.toggleSettings, 1)
  assert.equal(calls.switchedTo, "settings")
})

test("a programmatic open never closes the panel", () => {
  const { controller, panel, calls } = buildEnvironment({
    open: true,
    activeTab: "timeline-feed",
  })

  controller.openTabByName("timeline-feed")

  assert.equal(panel.classList.contains("open"), true)
  assert.equal(calls.toggleSettings, 0)
})

test("a click without a tab name does nothing", () => {
  const { controller, panel, calls } = buildEnvironment({
    open: true,
    activeTab: "settings",
  })

  controller.openTab({ currentTarget: { dataset: {} } })

  assert.equal(panel.classList.contains("open"), true)
  assert.equal(calls.toggleSettings, 0)
})

test("the keyboard shortcut toggles the same way the button does", () => {
  const { controller, panel, calls } = buildEnvironment({
    open: true,
    activeTab: "settings",
  })

  controller.requestTab("settings")

  assert.equal(panel.classList.contains("open"), false)
  assert.equal(calls.toggleSettings, 1)
})

test("cluster buttons report their expanded state to assistive tech", () => {
  const { controller, clusterButtons } = buildEnvironment({
    open: true,
    activeTab: "settings",
    stubMarkActive: false,
  })

  controller.markActiveClusterButton("layers")

  assert.equal(clusterButtons[0].attributes["aria-expanded"], "false")
  assert.equal(clusterButtons[1].attributes["aria-expanded"], "true")

  controller.markActiveClusterButton(null)

  assert.equal(clusterButtons[1].attributes["aria-expanded"], "false")
})

test("buttons that don't drive the panel are left untouched", () => {
  const { controller, nonPanelButton } = buildEnvironment({
    open: true,
    activeTab: "settings",
    stubMarkActive: false,
  })

  controller.markActiveClusterButton("layers")

  assert.deepEqual(nonPanelButton.attributes, {})
})
