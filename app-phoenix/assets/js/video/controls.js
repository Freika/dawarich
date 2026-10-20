import { studioQueryAll, studioQuery, studioValue } from "../studios/dom.js"
import { defaultSettings, formatFor } from "./state.js"

const find = (root, name) => studioQuery(root, `[data-video-${name}]`)
const findAll = (root, name) => [
  ...studioQueryAll(root, `[data-video-${name}]`),
]

const percent = (value) => `${Math.round(value)}%`
const LABELS = {
  duration_sec: (value) => `${value}s`,
  hud_scale: percent,
  track_width: percent,
  fog_opacity: percent,
  fog_color: (value) => value.toUpperCase(),
  track_color: (value) => value.toUpperCase(),
}

function inputValue(input) {
  if (input.type === "checkbox") return input.checked
  if (input.type === "range" || input.type === "number")
    return Number(input.value)
  return input.value
}

function markChoice(buttons, attribute, value) {
  for (const button of buttons) {
    const active = studioValue(button, attribute) === value
    button.setAttribute("aria-checked", String(active))
    button.classList.toggle("btn-primary", active)
    button.classList.toggle("btn-ghost", !active)
  }
}

export function formatLabel(root, settings) {
  const option = findAll(root, "format").find(
    (button) => studioValue(button, "videoFormat") === settings.format,
  )
  return (option?.dataset.label ?? option?.dataset.formatLabel) ?? settings.format
}

export function themeName(root, settings) {
  const swatch = findAll(root, "theme").find(
    (button) => studioValue(button, "videoTheme") === settings.theme,
  )
  return (swatch?.dataset.name ?? swatch?.dataset.themeName) ?? settings.theme
}

export function syncVideoControls(root, settings, activeElement = null) {
  for (const label of findAll(root, "label")) {
    const name = studioValue(label, "videoLabel")
    if (LABELS[name]) label.textContent = LABELS[name](settings[name])
  }
  const fog = find(root, "fog-controls")
  if (fog) {
    const selected = settings.visualization_mode === "fog"
    fog.classList.toggle("hidden", !selected)
    fog.setAttribute("aria-hidden", String(!selected))
    for (const input of findAll(root, "setting"))
      if (["fog_opacity", "fog_color"].includes(studioValue(input, "videoSetting")))
        input.disabled = !selected
  }
  markChoice(findAll(root, "mode"), "videoMode", settings.visualization_mode)
  markChoice(findAll(root, "format"), "videoFormat", settings.format)
  for (const input of findAll(root, "setting")) {
    const value = settings[studioValue(input, "videoSetting")]
    if (input.type === "checkbox") input.checked = Boolean(value)
    else if (activeElement !== input) input.value = value
  }
  for (const swatch of findAll(root, "theme")) {
    const active = studioValue(swatch, "videoTheme") === settings.theme
    swatch.setAttribute("aria-pressed", String(active))
    swatch.classList.toggle("ring-2", active)
    swatch.classList.toggle("ring-offset-1", active)
  }
  const themeLabel = find(root, "theme-label")
  if (themeLabel) themeLabel.textContent = themeName(root, settings)
  const dims = find(root, "format-dims")
  if (dims) {
    const { width, height } = formatFor(settings)
    dims.textContent = `${width} × ${height} · ${settings.duration_sec}s · 30 fps`
  }
}

export function bindVideoControls({ root, studio, window: win }) {
  const listeners = []
  const on = (target, type, handler) => {
    if (!target) return
    target.addEventListener(type, handler)
    listeners.push([target, type, handler])
  }
  const action = (name, handler) => on(find(root, name), "click", handler)

  action("render", () => studio.render())
  action("cancel", () => studio.cancel())
  action("save", () => studio.save())
  action("close", () => studio.close())
  action("switch", () => studio.switchStudio())
  action("load", () => studio.applyDates())
  const dialog = find(root, "dialog")
  on(dialog, "close", () => {
    if (!dialog.open) studio.close()
  })
  for (const swatch of findAll(root, "theme"))
    on(swatch, "click", () =>
      studio.change({ theme: studioValue(swatch, "videoTheme") }),
    )
  for (const button of findAll(root, "format"))
    on(button, "click", () =>
      studio.change({ format: studioValue(button, "videoFormat") }),
    )
  for (const button of findAll(root, "mode"))
    on(button, "click", () =>
      studio.change({ visualization_mode: studioValue(button, "videoMode") }),
    )
  for (const button of findAll(root, "reset"))
    on(button, "click", () => {
      const name = studioValue(button, "videoReset")
      studio.change({ [name]: defaultSettings()[name] })
    })
  for (const input of findAll(root, "setting")) {
    const update = () =>
      studio.change({ [studioValue(input, "videoSetting")]: inputValue(input) })
    on(input, input.type === "checkbox" ? "change" : "input", update)
  }
  on(win, "resize", () => studio.resize())

  return () => {
    for (const [target, type, handler] of listeners)
      target.removeEventListener(type, handler)
    listeners.length = 0
  }
}
