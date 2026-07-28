import { Controller } from "@hotwired/stimulus"
import { SettingsManager } from "maps_maplibre/utils/settings_manager"
import { extendTokens, loadThemeTokens } from "poster_studio/data/theme_loader"
import Flash from "./flash_controller"

// Note: the tiles only carry coarse road kinds, so the secondary/tertiary
// poster tokens have no effect on the map and get no picker here.
const TOKEN_KEYS = [
  "bg",
  "water",
  "parks",
  "buildings",
  "railway",
  "boundaries",
  "road_motorway",
  "road_primary",
  "road_residential",
  "road_default",
]

const SAVE_DEBOUNCE_MS = 150

// Custom map colors editor in the Appearance settings section. Seeds the
// token pickers from the stored custom theme (or a clicked preset), then
// persists and re-applies the live map style on every change.
export default class extends Controller {
  static targets = [
    "styleSelect",
    "block",
    "swatch",
    "token",
    "tokenValue",
    "presetLabel",
  ]

  connect() {
    this.onStyleSynced = (event) => this.syncVisibility(event.detail?.style)
    document.addEventListener("map-style:synced", this.onStyleSynced)
    if (this.hasStyleSelectTarget) {
      this.syncVisibility(this.styleSelectTarget.value)
    }
  }

  disconnect() {
    document.removeEventListener("map-style:synced", this.onStyleSynced)
    clearTimeout(this.debounce)
  }

  styleChanged(event) {
    this.syncVisibility(event.target.value)
  }

  async pickPreset(event) {
    const button = event.currentTarget
    try {
      const raw = await loadThemeTokens(button.dataset.key)
      const tokens = this.pickTokenKeys(raw)
      // Activate first: syncVisibility re-seeds the pickers from the stored
      // theme, so the clicked preset must populate after it.
      await this.activateCustomStyle()
      this.populate({ base: button.dataset.key, tokens })
      if (this.hasBlockTarget) this.blockTarget.open = true
      this.scheduleSave()
    } catch (error) {
      Flash.show("error", `Failed to load theme preset: ${error.message}`)
    }
  }

  // Clicking a theme swatch from any built-in style switches the map to
  // the Custom style with that theme — no need to find it in the select.
  async activateCustomStyle() {
    if (
      this.hasStyleSelectTarget &&
      this.styleSelectTarget.value !== "custom"
    ) {
      this.styleSelectTarget.value = "custom"
    }
    this.syncVisibility("custom")
    await SettingsManager.updateSetting("mapStyle", "custom")
  }

  tokenChanged(event) {
    this.updateTokenLabel(event.target)
    this.scheduleSave()
  }

  syncVisibility(styleName) {
    if (!this.hasBlockTarget) return
    const custom = styleName === "custom"
    this.blockTarget.classList.toggle("hidden", !custom)
    if (custom) this.populate(this.storedTheme)
  }

  scheduleSave() {
    clearTimeout(this.debounce)
    this.debounce = setTimeout(() => this.save(), SAVE_DEBOUNCE_MS)
  }

  async save() {
    await SettingsManager.updateSetting("customTheme", this.currentTheme)
    this.mapController?.applyMapStyle("custom")
  }

  populate({ base, tokens }) {
    this.base = base
    this.tokenTargets.forEach((input) => {
      const value = tokens[input.dataset.token]
      if (value) input.value = value
      this.updateTokenLabel(input)
    })
    this.markSelectedSwatch(base)
    this.updatePresetLabel(base)
  }

  get currentTheme() {
    const tokens = {}
    this.tokenTargets.forEach((input) => {
      tokens[input.dataset.token] = input.value
    })
    return { base: this.base || "noir", tokens }
  }

  get storedTheme() {
    const stored = SettingsManager.getSetting("customTheme") || {}
    return {
      base: stored.base || "noir",
      tokens: stored.tokens || {},
    }
  }

  pickTokenKeys(raw) {
    const derived = extendTokens(raw)
    const tokens = {}
    TOKEN_KEYS.forEach((key) => {
      const value = raw[key] ?? derived[key]
      if (value) tokens[key] = value
    })
    return tokens
  }

  updateTokenLabel(input) {
    const label = this.tokenValueTargets.find(
      (el) => el.dataset.token === input.dataset.token,
    )
    if (label) label.textContent = input.value.toUpperCase()
  }

  markSelectedSwatch(base) {
    this.swatchTargets.forEach((swatch) => {
      const selected = swatch.dataset.key === base
      swatch.classList.toggle("ring-2", selected)
      swatch.setAttribute("aria-pressed", String(selected))
    })
  }

  updatePresetLabel(base) {
    if (!this.hasPresetLabelTarget) return
    const swatch = this.swatchTargets.find((el) => el.dataset.key === base)
    this.presetLabelTarget.textContent = swatch
      ? `Based on: ${swatch.dataset.name}`
      : ""
  }

  get mapController() {
    const container = document.getElementById("maps-maplibre-container")
    return (
      container &&
      this.application.getControllerForElementAndIdentifier(
        container,
        "maps--maplibre",
      )
    )
  }
}
