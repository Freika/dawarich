import Flash from "controllers/flash_controller"
import { translate } from "i18n"
import { extendTokens, loadThemeTokens } from "poster_studio/data/theme_loader"

const RESTYLE_DEBOUNCE_MS = 150

/**
 * Poster theme: preset picking, token edits and the debounced restyle.
 * Mixed into the controller; `this` is the controller.
 */
export const themePicker = {
  scheduleRestyle() {
    clearTimeout(this.restyleTimer)
    this.restyleTimer = setTimeout(() => {
      this.previewMap?.setStyle(this.posterStyle())
      this.redrawOverlay()
    }, RESTYLE_DEBOUNCE_MS)
  },

  // ===== Theme =====

  initialThemeKey() {
    return this.swatchTargets[0]?.dataset.key || "blueprint"
  },

  async seedTheme(key) {
    const raw = await loadThemeTokens(key)
    this.tokens = { ...extendTokens(raw), ...raw }
    this.themeBase = key
    this.themeName =
      this.swatchTargets.find((el) => el.dataset.key === key)?.dataset.name ||
      raw.name ||
      key
    this.markSwatch(key)
    if (this.hasThemeLabelTarget)
      this.themeLabelTarget.textContent = this.themeName
    this.tokenTargets.forEach((input) => {
      const value = this.tokens[input.dataset.token]
      if (value) input.value = value
      this.syncTokenLabel(input)
    })
  },

  async pickTheme(event) {
    try {
      await this.seedTheme(event.currentTarget.dataset.key)
      this.scheduleRestyle()
      this.updateSummary()
    } catch (error) {
      Flash.show(
        "error",
        translate("poster.theme_load_failed", { error: error.message }),
      )
    }
  },

  tokenChanged(event) {
    this.tokens[event.target.dataset.token] = event.target.value
    this.syncTokenLabel(event.target)
    this.scheduleRestyle()
  },

  syncTokenLabel(input) {
    const label = this.tokenValueTargets.find(
      (el) => el.dataset.token === input.dataset.token,
    )
    if (label) label.textContent = input.value.toUpperCase()
  },

  markSwatch(key) {
    this.swatchTargets.forEach((swatch) => {
      swatch.classList.toggle("ring-2", swatch.dataset.key === key)
    })
  },
}
