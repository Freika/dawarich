import { defaultSettings, formatFor } from "video_studio/studio_state"

export const controls = {
  selectTheme(event) {
    this.settings.theme = event.currentTarget.dataset.themeKey
    this.settingsChanged()
  },
  resetTrackColor() {
    this.settings.track_color = defaultSettings().track_color
    this.settingsChanged()
  },
  resetFogColor() {
    this.settings.fog_color = defaultSettings().fog_color
    this.settingsChanged()
  },
  selectVisualizationMode(event) {
    this.settings.visualization_mode =
      event.currentTarget.dataset.visualizationMode
    this.settingsChanged()
  },
  selectFormat(event) {
    this.settings.format = event.currentTarget.dataset.format
    this.settingsChanged()
  },
  updateSetting(event) {
    const { setting } = event.currentTarget.dataset
    const input = event.currentTarget
    const value =
      input.type === "checkbox"
        ? input.checked
        : input.type === "range" || input.type === "number"
          ? Number(input.value)
          : input.value

    this.settings[setting] = value
    this.settingsChanged()
  },
  syncControls() {
    if (this.hasDurationLabelTarget) {
      this.durationLabelTarget.textContent = `${this.settings.duration_sec}s`
    }
    if (this.hasHudScaleLabelTarget) {
      this.hudScaleLabelTarget.textContent = `${Math.round(this.settings.hud_scale)}%`
    }
    if (this.hasTrackWidthLabelTarget) {
      this.trackWidthLabelTarget.textContent = `${Math.round(this.settings.track_width)}%`
    }
    if (this.hasFogOpacityLabelTarget) {
      this.fogOpacityLabelTarget.textContent = `${Math.round(this.settings.fog_opacity)}%`
    }
    if (this.hasFogColorLabelTarget) {
      this.fogColorLabelTarget.textContent =
        this.settings.fog_color.toUpperCase()
    }
    if (this.hasTrackColorLabelTarget) {
      this.trackColorLabelTarget.textContent =
        this.settings.track_color.toUpperCase()
    }
    if (this.hasFogControlsTarget) {
      const fogSelected = this.settings.visualization_mode === "fog"
      this.fogControlsTarget.classList.toggle("hidden", !fogSelected)
      this.fogControlsTarget.setAttribute("aria-hidden", String(!fogSelected))
      for (const control of this.fogControlsTarget.querySelectorAll(
        "input, button",
      )) {
        control.disabled = !fogSelected
      }
    }
    for (const button of this.visualizationModeTargets) {
      const active =
        button.dataset.visualizationMode === this.settings.visualization_mode
      button.setAttribute("aria-checked", String(active))
      button.classList.toggle("btn-primary", active)
      button.classList.toggle("btn-ghost", !active)
    }
    for (const button of this.formatOptionTargets) {
      const active = button.dataset.format === this.settings.format
      button.setAttribute("aria-checked", String(active))
      button.classList.toggle("btn-primary", active)
      button.classList.toggle("btn-ghost", !active)
    }
    for (const input of this.element.querySelectorAll(
      "input[data-setting], select[data-setting]",
    )) {
      const value = this.settings[input.dataset.setting]
      if (input.type === "checkbox") input.checked = Boolean(value)
      else if (document.activeElement !== input) input.value = value
    }
    for (const swatch of this.themeSwatchTargets) {
      const active = swatch.dataset.themeKey === this.settings.theme
      swatch.setAttribute("aria-pressed", String(active))
      swatch.classList.toggle("ring-2", active)
      swatch.classList.toggle("ring-offset-1", active)
      if (active && this.hasThemeLabelTarget) {
        this.themeLabelTarget.textContent = swatch.dataset.themeName
      }
    }
    if (this.hasFormatDimsTarget) {
      const { width, height } = formatFor(this.settings)
      this.formatDimsTarget.textContent = `${width} × ${height} · ${this.settings.duration_sec}s · 30 fps`
    }
  },
  formatLabel() {
    const option = this.formatOptionTargets.find(
      (button) => button.dataset.format === this.settings.format,
    )
    return option?.dataset.formatLabel ?? this.settings.format
  },
}

const actions = new Set(
  "close switchToPoster selectTheme resetTrackColor resetFogColor selectVisualizationMode selectFormat updateSetting restoreSettings applyDateTimeRange render cancel save".split(
    " ",
  ),
)

export function bindControls(studio) {
  const listeners = []
  const on = (target, name, callback) => {
    target.addEventListener(name, callback)
    listeners.push([target, name, callback])
  }
  const invoke = async (event, external = false) => {
    const target = event.target.closest?.("[data-action]")
    if (!target || (external && studio.element.contains(target))) return
    for (const action of (target.dataset.action || "").split(/\s+/)) {
      const match = action.match(/^(?:(\w+)->)?video-studio#(\w+)$/)
      if (!match || (match[1] || "click") !== event.type) continue
      const method = match[2]
      if (external && method !== "restoreSettings") continue
      if (!actions.has(method) || typeof studio[method] !== "function") continue
      event.preventDefault()
      try {
        if (method === "restoreSettings" && !studio.provider)
          await studio.open()
        await studio[method]({ currentTarget: target, target })
      } catch (error) {
        if (studio.statusTarget) studio.statusTarget.textContent = error.message
      }
    }
  }
  for (const name of ["click", "input", "change"])
    on(studio.element, name, invoke)
  on(document, "click", (event) => invoke(event, true))
  on(document, "video-studio:open", (event) =>
    studio.open(event.detail?.provider),
  )
  on(window, "resize", () => {
    studio.resizeFrame()
    studio.previewMap?.resize()
  })
  return () => {
    for (const [target, name, callback] of listeners)
      target.removeEventListener(name, callback)
    listeners.length = 0
  }
}
