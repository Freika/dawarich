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

const liveSocket = new LiveSocket("/phoenix/live", Socket, {
  params: { _csrf_token: meta("phoenix-csrf-token") },
  hooks: { ChangelogWidget },
})
liveSocket.connect()
window.liveSocket = liveSocket

window.addEventListener("dawarich:flash-timeout", (event) => {
  window.setTimeout(() => event.target.querySelector("button")?.click(), 5000)
})

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
  if (param && token && new URL(link.href, window.location.href).origin === window.location.origin) {
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
    if (link.hasAttribute("phx-click")) return event.preventDefault()
    stop(event)
    submitMethodLink(link, link.getAttribute("data-turbo-method") || link.getAttribute("data-method"))
  },
  true,
)

document.addEventListener(
  "submit",
  (event) => {
    const message = confirmMessage(event.submitter) ?? confirmMessage(event.target)
    if (message !== null && !window.confirm(message)) stop(event)
  },
  true,
)
