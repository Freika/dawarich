import { defaultSettings, formatFor } from "./state.js"

const find = (root, name) => root.querySelector(`[data-video-${name}]`)
const findAll = (root, name) => [
  ...root.querySelectorAll(`[data-video-${name}]`),
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
    const active = button.dataset[attribute] === value
    button.setAttribute("aria-checked", String(active))
    button.classList.toggle("btn-primary", active)
    button.classList.toggle("btn-ghost", !active)
  }
}

export function formatLabel(root, settings) {
  const option = findAll(root, "format").find(
    (button) => button.dataset.format === settings.format,
  )
  return option?.dataset.label ?? settings.format
}

export function themeName(root, settings) {
  const swatch = findAll(root, "theme").find(
    (button) => button.dataset.key === settings.theme,
  )
  return swatch?.dataset.name ?? settings.theme
}

export function syncVideoControls(root, settings, activeElement = null) {
  for (const label of findAll(root, "label")) {
    const name = label.dataset.videoLabel
    if (LABELS[name]) label.textContent = LABELS[name](settings[name])
  }
  const fog = find(root, "fog-controls")
  if (fog) {
    const selected = settings.visualization_mode === "fog"
    fog.classList.toggle("hidden", !selected)
    fog.setAttribute("aria-hidden", String(!selected))
    for (const input of findAll(root, "setting"))
      if (["fog_opacity", "fog_color"].includes(input.dataset.videoSetting))
        input.disabled = !selected
  }
  markChoice(findAll(root, "mode"), "mode", settings.visualization_mode)
  markChoice(findAll(root, "format"), "format", settings.format)
  for (const input of findAll(root, "setting")) {
    const value = settings[input.dataset.videoSetting]
    if (input.type === "checkbox") input.checked = Boolean(value)
    else if (activeElement !== input) input.value = value
  }
  for (const swatch of findAll(root, "theme")) {
    const active = swatch.dataset.key === settings.theme
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
  on(find(root, "dialog"), "close", () => studio.close())
  for (const swatch of findAll(root, "theme"))
    on(swatch, "click", () => studio.change({ theme: swatch.dataset.key }))
  for (const button of findAll(root, "format"))
    on(button, "click", () => studio.change({ format: button.dataset.format }))
  for (const button of findAll(root, "mode"))
    on(button, "click", () =>
      studio.change({ visualization_mode: button.dataset.mode }),
    )
  for (const button of findAll(root, "reset"))
    on(button, "click", () => {
      const name = button.dataset.videoReset
      studio.change({ [name]: defaultSettings()[name] })
    })
  for (const input of findAll(root, "setting")) {
    const update = () =>
      studio.change({ [input.dataset.videoSetting]: inputValue(input) })
    on(input, input.type === "checkbox" ? "change" : "input", update)
  }
  on(win, "resize", () => studio.resize())

  return () => {
    for (const [target, type, handler] of listeners)
      target.removeEventListener(type, handler)
    listeners.length = 0
  }
}
