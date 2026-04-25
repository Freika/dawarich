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
    // Two instances connect per page (settings panel + button cluster); the
    // module-level guard below makes sure document listeners bind only once.

    // Honor ?panel=timeline on first load by opening the panel and activating
    // the Timeline tab. `openTabByName` both opens the panel (maps--maplibre
    // controller's toggleSettings, so the `.open` class lands) AND activates
    // the tab — necessary because `.timeline-expanded` positions the panel at
    // `left: -720px`, which stays off-screen until `.open` is added.
    // Defer to the next frame so the maps--maplibre controller has connected
    // and its target queries resolve.
    const params = new URLSearchParams(window.location.search)
    if (params.get("panel") === "timeline") {
      requestAnimationFrame(() => this.openTabByName("timeline-feed"))
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
      // Don't hijack modified combos — Cmd+Shift+C (DevTools picker),
      // Ctrl+L (address bar), etc. must stay with the browser.
      if (e.metaKey || e.ctrlKey || e.altKey || e.shiftKey) return

      const keyToTab = {
        t: "timeline-feed",
        T: "timeline-feed",
        l: "layers",
        L: "layers",
        "/": "search",
        c: "tools",
        C: "tools",
        s: "settings",
        S: "settings",
      }
      const tab = keyToTab[e.key]
      if (tab) {
        e.preventDefault()
        this.openTabByName(tab)
        return
      }

      // Replay isn't a tab — it toggles a separate panel. Wire R into the
      // same hotkey handler so it shares the input/modifier-key guards
      // already established above.
      if (e.key === "r" || e.key === "R") {
        const mapContainer = document.getElementById("maps-maplibre-container")
        if (!mapContainer) return
        const maplibreController =
          this.application.getControllerForElementAndIdentifier(
            mapContainer,
            "maps--maplibre",
          )
        if (maplibreController?.toggleReplay) {
          e.preventDefault()
          maplibreController.toggleReplay()
        }
      }
    }
    document.addEventListener("keydown", this.boundClusterKeys)

    // Clicking a visit pin on the map dispatches `timeline:open-visit` — open
    // the Timeline tab so the list + halo are visible (timeline_feed_controller
    // handles day selection on its own).
    this.boundOpenVisit = () => this.openTabByName("timeline-feed")
    document.addEventListener("timeline:open-visit", this.boundOpenVisit)

    // Same for tracks — clicking a track line on the map opens the Timeline
    // tab and expands the matching journey entry inline.
    this.boundOpenTrack = () => this.openTabByName("timeline-feed")
    document.addEventListener("timeline:open-track", this.boundOpenTrack)

    // Clear cluster active state when the panel is dismissed via the
    // header's X button (or any path that goes through #toggleSettings).
    this.boundPanelClosed = () => this.markActiveClusterButton(null)
    document.addEventListener("map-panel:closed", this.boundPanelClosed)
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
    if (this.boundOpenVisit) {
      document.removeEventListener("timeline:open-visit", this.boundOpenVisit)
      this.boundOpenVisit = null
    }
    if (this.boundOpenTrack) {
      document.removeEventListener("timeline:open-track", this.boundOpenTrack)
      this.boundOpenTrack = null
    }
    if (this.boundPanelClosed) {
      document.removeEventListener("map-panel:closed", this.boundPanelClosed)
      this.boundPanelClosed = null
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
   * panel's map-panel controller instance. If the panel is already open
   * AND `tabName` is the active tab, toggle the panel closed — gives the
   * cluster button a "press again to dismiss" affordance now that the
   * cluster doubles as the panel's tab strip.
   */
  openTabByName(tabName) {
    const panel = document.querySelector(".map-control-panel")
    const mapContainer = document.getElementById("maps-maplibre-container")

    const maplibreController =
      mapContainer &&
      this.application.getControllerForElementAndIdentifier(
        mapContainer,
        "maps--maplibre",
      )

    if (panel && panel.classList.contains("open")) {
      const activeContent = panel.querySelector(
        ".tab-content.active[data-tab-content]",
      )
      const activeTab = activeContent?.dataset?.tabContent
      if (activeTab === tabName) {
        if (maplibreController?.toggleSettings) {
          maplibreController.toggleSettings()
          this.markActiveClusterButton(null)
        }
        return
      }
    }

    if (panel && mapContainer && !panel.classList.contains("open")) {
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
   * Pass `null` to clear every cluster button — used when the panel is
   * dismissed (no tab is "active" because the panel itself is hidden).
   */
  markActiveClusterButton(activeTab) {
    const buttons = document.querySelectorAll(".map-button-cluster__btn")
    for (const btn of buttons) {
      btn.classList.toggle(
        "map-button-cluster__btn--active",
        Boolean(activeTab) && btn.dataset.tab === activeTab,
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
