import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

const meta = (name) =>
  document.querySelector(`meta[name='${name}']`)?.getAttribute("content")

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

const bridges = new WeakMap()

const appendRailsFlash = (content) => {
  const container = document.getElementById("flash-messages")
  if (!container) return
  for (const alert of [...content.querySelectorAll("[role='alert']")]) {
    container.appendChild(alert)
    if (alert.getAttribute("data-removals-timeout-value") === "5000") {
      window.setTimeout(() => alert.remove(), 5000)
    }
  }
}

const controllerIdentifiers = (root) =>
  [root, ...root.querySelectorAll("[data-controller]")]
    .flatMap((node) =>
      (node.getAttribute("data-controller") || "").split(/\s+/),
    )
    .filter(
      (identifier, index, all) =>
        identifier !== "" && all.indexOf(identifier) === index,
    )

const registerControllers = async (app, root) => {
  for (const identifier of controllerIdentifiers(root)) {
    const path = identifier.replace(/--/g, "/").replace(/-/g, "_")
    const module = await import(`controllers/${path}_controller`)
    app.register(identifier, module.default)
  }
}

const startStimulus = async (element) => {
  const { Application } = await import("@hotwired/stimulus")
  const app = Application.start(element)
  await registerControllers(app, element)
  return app
}

const submitStream = async (event, bridge) => {
  const form = event.target.closest?.("form[data-sharing-modal-target='form']")
  if (!form) return
  event.preventDefault()
  const response = await fetch(form.action, {
    method: "POST",
    body: new URLSearchParams(new FormData(form)),
    headers: {
      Accept: "text/vnd.turbo-stream.html, text/html, application/xhtml+xml",
      "X-CSRF-Token": meta("csrf-token") || "",
    },
    credentials: "same-origin",
  })
  const template = document.createElement("template")
  template.innerHTML = await response.text()
  for (const stream of template.content.querySelectorAll("turbo-stream")) {
    const content = stream.querySelector("template")?.content
    if (!content) continue
    if (stream.getAttribute("action") === "replace") {
      document
        .getElementById(stream.getAttribute("target"))
        ?.replaceWith(content)
    } else if (stream.getAttribute("target") === "flash-messages") {
      bridge.flash(content)
    }
  }
}

const railsBridge = (element) => {
  if (bridges.has(element)) return bridges.get(element)
  const bridge = { flash: appendRailsFlash }
  bridge.onSubmit = (event) => submitStream(event, bridge)
  element.addEventListener("submit", bridge.onSubmit)
  bridge.ready = startStimulus(element)
  bridges.set(element, bridge)
  return bridge
}

const RailsStimulus = {
  mounted() {
    this.bridge = railsBridge(this.el)
    this.reconnected()
  },
  reconnected() {
    this.bridge.flash = (content) => {
      const alert = content.querySelector("[role='alert']")
      this.pushEvent("rails_flash", {
        type: alert?.classList.contains("alert-error") ? "error" : "success",
        message: alert?.querySelector("span")?.textContent || "",
      })
    }
  },
  disconnected() {
    this.bridge.flash = appendRailsFlash
  },
  destroyed() {
    const bridge = bridges.get(this.el)
    if (!bridge) return
    this.el.removeEventListener("submit", bridge.onSubmit)
    bridge.ready.then((app) => app.stop())
    bridges.delete(this.el)
  },
}

const liveSocket = new LiveSocket("/phoenix/live", Socket, {
  params: { _csrf_token: meta("phoenix-csrf-token") },
  hooks: { ChangelogWidget, RailsStimulus },
})
liveSocket.connect()
window.liveSocket = liveSocket

const bootRailsBridges = () => {
  for (const element of document.querySelectorAll("[phx-hook='RailsStimulus']"))
    railsBridge(element)
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", bootRailsBridges)
} else {
  bootRailsBridges()
}

const joined = () => liveSocket.main?.isConnected() === true

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
  if (joined()) return
  event.target
    .closest?.("[data-action~='click->removals#remove']")
    ?.closest("[data-controller~='removals']")
    ?.remove()
})
