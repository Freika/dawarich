import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { FamilyPage } from "family_page"
import {
  bootRailsBridges,
  MapShell,
  meta,
  RailsStimulus,
  watchFlashes,
} from "rails_bridge"

const ChangelogWidget = {
  mounted() {
    if (document.getElementById("chibichange-loader")) return
    const script = document.createElement("script")
    script.id = "chibichange-loader"
    script.src = this.el.dataset.changelogWidgetSrcValue
    script.async = true
    script.dataset.slug = this.el.dataset.changelogWidgetSlugValue
    script.dataset.version = this.el.dataset.changelogWidgetVersionValue
    script.dataset.consent = "granted"
    script.dataset.mount = "#chgtool-mount"
    document.head.appendChild(script)
  },
}

const turboOwns = (element) => {
  if (!window.Turbo || !element) return false
  const container = element.closest("[data-turbo]")
  return container
    ? container.getAttribute("data-turbo") === "true"
    : element.closest("turbo-frame") !== null
}

const liveSocket = new LiveSocket("/phoenix/live", Socket, {
  params: { _csrf_token: meta("phoenix-csrf-token") },
  hooks: { ChangelogWidget, RailsStimulus, MapShell, FamilyPage },
  dom: {
    onBeforeElUpdated(fromEl, toEl) {
      if (
        fromEl.matches(".navbar-end details") &&
        toEl.matches("details") &&
        fromEl.querySelector('a[href="/users/sign_out"]') &&
        toEl.querySelector('a[href="/users/sign_out"]')
      ) {
        toEl.toggleAttribute("open", fromEl.hasAttribute("open"))
      }
    },
  },
})
liveSocket.connect()
window.liveSocket = liveSocket

const bootTurboFrames = () => {
  if (!document.querySelector("turbo-frame[src]")) return
  import("@hotwired/turbo-rails").then(({ Turbo }) => {
    Turbo.session.drive = false
  })
}

const boot = () => {
  bootRailsBridges()
  bootTurboFrames()
  watchFlashes()
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", boot)
} else {
  boot()
}

const joined = () => liveSocket.main?.isConnected() === true

document.addEventListener("click", (event) => {
  if (!joined() && event.target.closest?.("a[data-phx-link]"))
    event.stopPropagation()
})

window.addEventListener("dawarich:flash-timeout", (event) => {
  window.setTimeout(() => event.target.querySelector("button")?.click(), 5000)
})

window.setTimeout(() => {
  if (joined()) return
  for (const button of document.querySelectorAll(
    "[data-removals-timeout-value='5000'] button",
  )) {
    button.click()
  }
}, 5000)

const confirmMessage = (element) =>
  element?.getAttribute("data-turbo-confirm") ??
  element?.getAttribute("data-confirm") ??
  null

const stop = (event) => {
  event.preventDefault()
  event.stopImmediatePropagation()
}

const submitMethodLink = (link, method) => {
  if (method.toLowerCase() === "get") {
    return window.open(link.href, link.target || "_self")
  }
  const form = document.createElement("form")
  const field = (name, value) => {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value
    form.appendChild(input)
  }
  const param = meta("csrf-param")
  const token = meta("csrf-token")
  form.method = "post"
  form.action = link.href
  if (link.target) form.target = link.target
  form.style.display = "none"
  field("_method", method)
  if (
    param &&
    token &&
    new URL(link.href, window.location.href).origin === window.location.origin
  ) {
    field(param, token)
  }
  const submit = document.createElement("input")
  submit.type = "submit"
  form.appendChild(submit)
  document.body.appendChild(form)
  submit.click()
}

document.addEventListener(
  "click",
  (event) => {
    const link = event.target.closest?.("a[data-turbo-method], a[data-method]")
    if (!link) return
    if (turboOwns(link)) return
    const message = confirmMessage(link)
    if (message !== null && !window.confirm(message)) return stop(event)
    if (link.hasAttribute("phx-click") && joined())
      return event.preventDefault()
    stop(event)
    submitMethodLink(
      link,
      link.getAttribute("data-turbo-method") ||
        link.getAttribute("data-method"),
    )
  },
  true,
)

document.addEventListener(
  "submit",
  (event) => {
    if (turboOwns(event.target)) return
    const message =
      confirmMessage(event.submitter) ?? confirmMessage(event.target)
    if (message !== null && !window.confirm(message)) return stop(event)
    if (event.target.hasAttribute?.("phx-submit") && !joined())
      event.stopImmediatePropagation()
  },
  true,
)

const dismissibleKey = (el) => `dismissed:${el.dataset.dismissibleKeyValue}`

for (const el of document.querySelectorAll("[data-dismissible-key-value]")) {
  try {
    if (localStorage.getItem(dismissibleKey(el)) === "1") el.remove()
  } catch (_e) {}
}

document.addEventListener("click", (event) => {
  const el = event.target.closest?.("[data-dismissible-key-value]")
  if (!el || !event.target.closest?.("button")) return
  try {
    localStorage.setItem(dismissibleKey(el), "1")
  } catch (_e) {}
  el.remove()
})

document.addEventListener("click", (event) => {
  const button = event.target.closest?.(
    "[data-action~='click->removals#remove']",
  )
  if (!button || (joined() && button.hasAttribute("phx-click"))) return
  button.closest("[data-controller~='removals']")?.remove()
})
