/** Overlay widgets for the video export preview, mirroring Remotion layouts. */

const LIGHT_MAP_STYLES = new Set(["light", "white"])

const DARK_THEME = {
  text: "#ffffff",
  textMuted: "rgba(255, 255, 255, 0.7)",
  cardBg: "rgba(0, 0, 0, 0.5)",
  gradientBottom: "linear-gradient(transparent, rgba(0, 0, 0, 0.7))",
  gradientTop: "linear-gradient(rgba(0, 0, 0, 0.6), transparent)",
}

const LIGHT_THEME = {
  text: "#1a1a2e",
  textMuted: "rgba(26, 26, 46, 0.65)",
  cardBg: "rgba(255, 255, 255, 0.7)",
  gradientBottom: "linear-gradient(transparent, rgba(255, 255, 255, 0.75))",
  gradientTop: "linear-gradient(rgba(255, 255, 255, 0.7), transparent)",
}

function formatTime(totalSeconds) {
  const s = Math.floor(totalSeconds)
  const m = Math.floor(s / 60)
  const sec = s % 60
  return `${m}:${sec.toString().padStart(2, "0")}`
}

function formatSpeed(kmh) {
  return kmh.toFixed(1)
}

function formatDistance(km) {
  return km < 1 ? `${(km * 1000).toFixed(0)} m` : `${km.toFixed(2)} km`
}

function createWidget(label, unit) {
  const el = document.createElement("div")
  el.className = "overlay-widget"
  el.style.cssText =
    "flex:1;text-align:center;font-family:system-ui,-apple-system,sans-serif;"

  const labelEl = document.createElement("div")
  labelEl.className = "overlay-label"
  labelEl.style.cssText =
    "font-size:7px;font-weight:500;text-transform:uppercase;letter-spacing:0.06em;opacity:0.7;margin-bottom:2px;"
  labelEl.textContent = label

  const valueEl = document.createElement("div")
  valueEl.className = "overlay-value"
  valueEl.style.cssText =
    "font-size:13px;font-weight:700;line-height:1.2;font-variant-numeric:tabular-nums;"
  valueEl.textContent = "0"

  const unitEl = document.createElement("div")
  unitEl.className = "overlay-unit"
  unitEl.style.cssText = "font-size:7px;opacity:0.6;margin-top:1px;"
  unitEl.textContent = unit

  el.append(labelEl, valueEl, unitEl)
  return { el, valueEl }
}

// ── Layout positioning ──────────────────────────────────────────────

const LAYOUT_CONFIGS = {
  // Landscape layouts
  bottom_bar: {
    container: "absolute;bottom:0;left:0;right:0;padding:4px 10px 8px;",
    bg: "gradient_bottom",
    arrange: "row",
  },
  corner_hud: {
    container: "absolute;bottom:6px;left:6px;right:6px;",
    bg: "cards",
    arrange: "corners",
  },
  bottom_left: {
    container: "absolute;bottom:6px;left:6px;",
    bg: "card",
    arrange: "compact",
  },
  cinematic_strip: {
    container: "absolute;bottom:0;left:0;right:0;padding:4px 10px;",
    bg: "gradient_bottom",
    arrange: "row_tight",
  },
  // Portrait layouts
  bottom_stack: {
    container: "absolute;bottom:6px;left:6px;right:6px;",
    bg: "card",
    arrange: "column",
  },
  bottom_row_card: {
    container: "absolute;bottom:6px;left:6px;right:6px;",
    bg: "card",
    arrange: "row",
  },
  split_bands: {
    container: "absolute;bottom:0;left:0;right:0;padding:6px 10px 8px;",
    bg: "gradient_bottom",
    arrange: "row",
  },
  right_rail: {
    container: "absolute;top:6px;bottom:6px;right:6px;width:50px;",
    bg: "card",
    arrange: "column",
  },
  floating_pills: {
    container: "absolute;bottom:8px;left:6px;right:6px;",
    bg: "pills",
    arrange: "row_pills",
  },
}

function applyArrangement(inner, arrange) {
  switch (arrange) {
    case "row":
      inner.style.cssText +=
        "display:flex;flex-direction:row;justify-content:space-around;align-items:flex-end;gap:8px;"
      break
    case "row_tight":
      inner.style.cssText +=
        "display:flex;flex-direction:row;justify-content:center;align-items:center;gap:12px;"
      break
    case "row_pills":
      inner.style.cssText +=
        "display:flex;flex-direction:row;justify-content:center;align-items:center;gap:6px;flex-wrap:wrap;"
      break
    case "column":
      inner.style.cssText +=
        "display:flex;flex-direction:column;justify-content:center;align-items:stretch;gap:6px;"
      break
    case "compact":
      inner.style.cssText +=
        "display:flex;flex-direction:row;align-items:center;gap:10px;"
      break
    case "corners":
      inner.style.cssText +=
        "display:flex;flex-direction:row;justify-content:space-between;align-items:flex-end;gap:4px;"
      break
  }
}

function applyBackground(el, bgType, theme) {
  switch (bgType) {
    case "gradient_bottom":
      el.style.background = theme.gradientBottom
      break
    case "gradient_top":
      el.style.background = theme.gradientTop
      break
    case "card":
      el.style.background = theme.cardBg
      el.style.backdropFilter = "blur(4px)"
      el.style.borderRadius = "6px"
      el.style.padding = "6px 8px"
      break
    case "cards":
      // Individual cards handled per-widget via pill styling
      break
    case "pills":
      // Individual pill backgrounds handled per-widget
      break
  }
}

function applyPillStyle(widgetEl, theme) {
  widgetEl.style.background = theme.cardBg
  widgetEl.style.backdropFilter = "blur(4px)"
  widgetEl.style.borderRadius = "10px"
  widgetEl.style.padding = "3px 8px"
}

export class PreviewOverlays {
  constructor(wrapperEl) {
    this.wrapper = wrapperEl
    this.root = null
    this.widgets = {}
    this.theme = DARK_THEME
    this.currentLayout = "bottom_bar"
    this.visibility = {
      time: true,
      speed: true,
      distance: true,
      track_name: true,
    }
  }

  mount() {
    if (this.root) this.destroy()

    this.root = document.createElement("div")
    this.root.style.cssText =
      "position:absolute;inset:0;pointer-events:none;z-index:10;overflow:hidden;"

    this.widgets = {
      time: createWidget("TIME", ""),
      speed: createWidget("SPEED", "km/h"),
      distance: createWidget("DIST", ""),
      track_name: createWidget("", ""),
    }
    // Track name widget has a simpler structure
    this.widgets.track_name.el.querySelector(".overlay-label").style.display =
      "none"
    this.widgets.track_name.el.querySelector(".overlay-unit").style.display =
      "none"
    this.widgets.track_name.valueEl.style.fontSize = "10px"
    this.widgets.track_name.valueEl.style.fontWeight = "600"

    this.wrapper.appendChild(this.root)
    this._rebuild()
  }

  updateFrame({ elapsedSeconds, speed, distance }) {
    if (this.widgets.time) {
      this.widgets.time.valueEl.textContent = formatTime(elapsedSeconds)
    }
    if (this.widgets.speed) {
      this.widgets.speed.valueEl.textContent = formatSpeed(speed)
    }
    if (this.widgets.distance) {
      this.widgets.distance.valueEl.textContent = formatDistance(distance)
    }
  }

  updateLayout(layoutName) {
    this.currentLayout = layoutName
    this._rebuild()
  }

  updateTheme(mapStyle) {
    this.theme = LIGHT_MAP_STYLES.has(mapStyle) ? LIGHT_THEME : DARK_THEME
    this._applyThemeColors()
  }

  updateVisibility(overlays) {
    this.visibility = { ...this.visibility, ...overlays }
    this._rebuild()
  }

  updateTrackName(name) {
    if (this.widgets.track_name) {
      this.widgets.track_name.valueEl.textContent = name || ""
    }
  }

  destroy() {
    if (this.root) {
      this.root.remove()
      this.root = null
    }
    this.widgets = {}
  }

  // ── Private ───────────────────────────────────────────────────────

  _rebuild() {
    if (!this.root) return

    // Remove existing inner content
    this.root.innerHTML = ""

    const cfg = LAYOUT_CONFIGS[this.currentLayout] || LAYOUT_CONFIGS.bottom_bar

    const container = document.createElement("div")
    container.style.cssText = `position:${cfg.container}`

    const inner = document.createElement("div")
    applyBackground(container, cfg.bg, this.theme)
    applyArrangement(inner, cfg.arrange)

    const visibleWidgets = this._visibleWidgetEntries()
    const usePerWidgetBg = cfg.bg === "cards" || cfg.bg === "pills"

    for (const [, widget] of visibleWidgets) {
      if (usePerWidgetBg) {
        applyPillStyle(widget.el, this.theme)
      } else {
        widget.el.style.background = ""
        widget.el.style.backdropFilter = ""
        widget.el.style.borderRadius = ""
        widget.el.style.padding = ""
      }
      inner.appendChild(widget.el)
    }

    container.appendChild(inner)
    this.root.appendChild(container)
    this._applyThemeColors()
  }

  _visibleWidgetEntries() {
    const order = ["time", "speed", "distance", "track_name"]
    return order
      .filter((key) => this.visibility[key] && this.widgets[key])
      .map((key) => [key, this.widgets[key]])
  }

  _applyThemeColors() {
    if (!this.root) return
    for (const widget of Object.values(this.widgets)) {
      widget.valueEl.style.color = this.theme.text
      const label = widget.el.querySelector(".overlay-label")
      if (label) label.style.color = this.theme.textMuted
      const unit = widget.el.querySelector(".overlay-unit")
      if (unit) unit.style.color = this.theme.textMuted
    }
  }
}
