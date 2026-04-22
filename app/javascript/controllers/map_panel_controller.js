import { Controller } from "@hotwired/stimulus"

// Module-level flag so the document-level keyboard shortcuts and tab-change
// mirror listeners are only bound once, even when multiple map-panel
// controller instances exist on the page (e.g. the settings panel and the
// map-edge button cluster both share this controller).
let clusterGlobalHandlersBoundBy = null

/**
 * Map Panel Controller
 * Handles tab switching in the map control panel, including the Timeline tab's
 * panel-expansion behavior (wide panel + map resize).
 */
export default class extends Controller {
  static targets = ["tabButton", "tabContent", "title"]

  // Tab title mappings
  static titles = {
    search: "Search",
    layers: "Map Layers",
    "timeline-feed": "Timeline",
    tools: "Tools",
    links: "Links",
    settings: "Settings",
  }

  connect() {
    console.log("[Map Panel] Connected")

    // Honor ?panel=timeline on first load by activating the Timeline tab.
    // Defer to the next frame so other controllers (e.g., MapLibre) have a
    // chance to connect first and target queries resolve.
    const params = new URLSearchParams(window.location.search)
    if (params.get("panel") === "timeline") {
      requestAnimationFrame(() => this.activateTab("timeline-feed"))
    }

    // Only bind the document-level listeners from a single instance to avoid
    // double-firing when both the settings panel and the button cluster are
    // present on the page.
    if (clusterGlobalHandlersBoundBy !== null) {
      return
    }
    clusterGlobalHandlersBoundBy = this

    // Keep the map-edge button cluster in sync when tabs change from any
    // source (clicks in the panel, programmatic switches, etc.).
    this.boundTabChangedListener = (e) => {
      this.markActiveClusterButton(e.detail?.tab)
    }
    document.addEventListener(
      "map-panel:tab-changed",
      this.boundTabChangedListener,
    )

    // Keyboard shortcuts for the button cluster — bound at document level so
    // they fire regardless of which map-panel instance is focused.
    this.boundClusterKeys = (e) => {
      if (
        e.target &&
        typeof e.target.matches === "function" &&
        e.target.matches("input, textarea, select, [contenteditable]")
      ) {
        return
      }
      const keyToTab = {
        t: "timeline-feed",
        T: "timeline-feed",
        l: "layers",
        L: "layers",
        "/": "search",
        c: "tools",
        C: "tools",
      }
      const tab = keyToTab[e.key]
      if (!tab) return
      e.preventDefault()
      this.openTabByName(tab)
    }
    document.addEventListener("keydown", this.boundClusterKeys)
  }

  disconnect() {
    if (this.boundClusterKeys) {
      document.removeEventListener("keydown", this.boundClusterKeys)
      this.boundClusterKeys = null
    }
    if (this.boundTabChangedListener) {
      document.removeEventListener(
        "map-panel:tab-changed",
        this.boundTabChangedListener,
      )
      this.boundTabChangedListener = null
    }
    if (clusterGlobalHandlersBoundBy === this) {
      clusterGlobalHandlersBoundBy = null
    }
  }

  /**
   * Open the settings panel to a specific tab.
   * Triggered by the map-edge button cluster and keyboard shortcuts.
   */
  openTab(event) {
    const button = event.currentTarget
    const tabName = button?.dataset?.tab
    if (!tabName) return
    this.openTabByName(tabName)
  }

  /**
   * Programmatic equivalent of openTab(event). Opens the settings panel
   * (via the maps--maplibre controller) and activates the given tab on the
   * panel's map-panel controller instance.
   */
  openTabByName(tabName) {
    const panel = document.querySelector(".map-control-panel")
    const mapContainer = document.getElementById("maps-maplibre-container")

    if (panel && mapContainer && !panel.classList.contains("open")) {
      const maplibreController =
        this.application.getControllerForElementAndIdentifier(
          mapContainer,
          "maps--maplibre",
        )
      if (maplibreController?.toggleSettings) {
        maplibreController.toggleSettings()
      }
    }

    if (panel) {
      const panelController =
        this.application.getControllerForElementAndIdentifier(
          panel,
          "map-panel",
        )
      if (panelController?.switchToTab) {
        panelController.switchToTab(tabName)
      }
    }

    this.markActiveClusterButton(tabName)
  }

  /**
   * Reflect the currently-active tab on the map-edge cluster buttons.
   */
  markActiveClusterButton(activeTab) {
    if (!activeTab) return
    const buttons = document.querySelectorAll(".map-button-cluster__btn")
    for (const btn of buttons) {
      btn.classList.toggle(
        "map-button-cluster__btn--active",
        btn.dataset.tab === activeTab,
      )
    }
  }

  /**
   * Switch to a different tab
   */
  switchTab(event) {
    const button = event.currentTarget
    const tabName = button.dataset.tab

    this.activateTab(tabName)
  }

  /**
   * Programmatically switch to a tab by name
   */
  switchToTab(tabName) {
    this.activateTab(tabName)
  }

  /**
   * Internal method to activate a tab
   */
  activateTab(tabName) {
    // Find the button for this tab
    const button = this.tabButtonTargets.find(
      (btn) => btn.dataset.tab === tabName,
    )

    // Update active button
    for (const btn of this.tabButtonTargets) {
      btn.classList.remove("active")
    }
    if (button) {
      button.classList.add("active")
    }

    // Update tab content
    for (const content of this.tabContentTargets) {
      const contentTab = content.dataset.tabContent
      if (contentTab === tabName) {
        content.classList.add("active")
      } else {
        content.classList.remove("active")
      }
    }

    // Update title
    if (this.hasTitleTarget) {
      this.titleTarget.textContent = this.constructor.titles[tabName] || tabName
    }

    // Toggle Timeline expansion on panel + container
    this.applyTimelineExpansion(tabName)

    // Dispatch event for other controllers to react
    document.dispatchEvent(
      new CustomEvent("map-panel:tab-changed", { detail: { tab: tabName } }),
    )
  }

  /**
   * Add / remove `timeline-expanded` on the panel and `panel-timeline-expanded`
   * on the maps container. Dispatch `map:resize-needed` once the CSS width/left
   * transition completes so MapLibre can re-measure its canvas.
   */
  applyTimelineExpansion(tabName) {
    const panel = document.querySelector(".map-control-panel")
    const container = document.querySelector(".maps-maplibre-container")

    const expanding = tabName === "timeline-feed"
    if (panel) {
      panel.classList.toggle("timeline-expanded", expanding)
    }
    if (container) {
      container.classList.toggle("panel-timeline-expanded", expanding)
    }

    if (!panel) return

    // One-shot transition listener — fire map:resize-needed once the panel
    // geometry has actually settled. Safe-guarded by a timeout fallback in
    // case the transition doesn't run (reduced-motion, no CSS, etc.).
    const resizer = (e) => {
      if (
        e.propertyName !== "width" &&
        e.propertyName !== "left" &&
        e.propertyName !== "max-width"
      ) {
        return
      }
      panel.removeEventListener("transitionend", resizer)
      if (fallback) clearTimeout(fallback)
      document.dispatchEvent(new CustomEvent("map:resize-needed"))
    }

    panel.addEventListener("transitionend", resizer)
    const fallback = setTimeout(() => {
      panel.removeEventListener("transitionend", resizer)
      document.dispatchEvent(new CustomEvent("map:resize-needed"))
    }, 500)
  }
}
