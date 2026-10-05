export const meta = (name) =>
  document.querySelector(`meta[name='${name}']`)?.getAttribute("content")

const bridges = new WeakMap()
const islands = new Set()
let streamBridge = null
window.StimulusIslands = islands
window.Stimulus ??= {
  getControllerForElementAndIdentifier: (element, identifier) => {
    for (const app of islands) {
      const controller = app.getControllerForElementAndIdentifier(
        element,
        identifier,
      )
      if (controller) return controller
    }
    return null
  },
}

export const appendRailsFlash = (content) => {
  const container = document.getElementById("flash-messages")
  if (!container) return
  for (const alert of [...content.querySelectorAll("[role='alert']")])
    container.appendChild(alert)
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
  const { lazyLoadControllersFrom } = await import("@hotwired/stimulus-loading")
  const app = new Application(element)
  await app.start()
  islands.add(app)
  await registerControllers(app, element)
  lazyLoadControllersFrom("controllers", app, element)
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

export const railsBridge = (element) => {
  if (bridges.has(element)) return bridges.get(element)
  const bridge = { pendingFlash: null }
  bridge.offlineFlash = (content) => {
    bridge.pendingFlash = content.cloneNode(true)
    appendRailsFlash(content)
  }
  bridge.flash = bridge.offlineFlash
  bridge.onSubmit = (event) => {
    streamBridge = bridge
    submitStream(event, bridge)
  }
  bridge.onStream = (event) => {
    const stream = event.target
    if (
      streamBridge !== bridge ||
      stream.getAttribute("action") !== "append" ||
      stream.getAttribute("target") !== "flash-messages"
    )
      return
    const content = stream.querySelector("template")?.content
    if (!content) return
    event.preventDefault()
    bridge.flash(content)
  }
  element.addEventListener("submit", bridge.onSubmit, true)
  document.addEventListener("turbo:before-stream-render", bridge.onStream)
  const controls = [...element.querySelectorAll("button, input, select, textarea")]
    .map((control) => [control, control.disabled])
  for (const [control] of controls) control.disabled = true
  bridge.ready = startStimulus(element).finally(() => {
    for (const [control, disabled] of controls) control.disabled = disabled
  })
  bridge.ready.then(() => enableForm(element))
  bridges.set(element, bridge)
  return bridge
}

const enableForm = (element) => {
  element.removeAttribute("inert")
  for (const fieldset of element.querySelectorAll("[data-rails-form-ready]"))
    fieldset.disabled = false
}

export const RailsStimulus = {
  mounted() {
    this.bridge = railsBridge(this.el)
    this.reconnected()
  },
  reconnected() {
    this.bridge.ready.then(() => enableForm(this.el))
    this.bridge.flash = (content) => {
      const alert = content.querySelector("[role='alert']")
      this.pushEvent("rails_flash", {
        type: alert?.classList.contains("alert-error") ? "error" : "success",
        message: alert?.querySelector("span")?.textContent || "",
      })
    }
    if (this.bridge.pendingFlash) {
      this.bridge.flash(this.bridge.pendingFlash)
      this.bridge.pendingFlash = null
    }
  },
  disconnected() {
    this.bridge.flash = this.bridge.offlineFlash
  },
  updated() {
    this.bridge.ready.then(() => enableForm(this.el))
  },
  destroyed() {
    const bridge = bridges.get(this.el)
    if (!bridge) return
    this.el.removeEventListener("submit", bridge.onSubmit, true)
    document.removeEventListener("turbo:before-stream-render", bridge.onStream)
    if (streamBridge === bridge) streamBridge = null
    bridge.ready.then((app) => {
      app.stop()
      islands.delete(app)
    })
    bridges.delete(this.el)
  },
}

const mapShell = () => import("map_shell")

export const MapShell = {
  mounted() {
    mapShell().then((shell) => shell.mount(this.el, this))
  },
  reconnected() {
    mapShell().then((shell) => shell.join(this))
  },
  disconnected() {
    mapShell().then((shell) => shell.leave(this))
  },
  destroyed() {
    mapShell().then((shell) => shell.unmount(this.el))
  },
}

export const bootRailsBridges = () => {
  for (const element of document.querySelectorAll("[phx-hook='RailsStimulus']"))
    railsBridge(element)
  for (const element of document.querySelectorAll("[phx-hook='MapShell']"))
    mapShell().then((shell) => shell.mount(element))
}

export const bootTurboFrames = () => {
  if (!document.querySelector("turbo-frame")) return
  return import("@hotwired/turbo-rails").then(({ Turbo }) => {
    Turbo.session.drive = false
  })
}

const expireRailsAlert = (node) => {
  if (
    node instanceof Element &&
    node.getAttribute("data-removals-timeout-value") === "5000" &&
    !node.querySelector("[phx-click]")
  )
    window.setTimeout(() => node.remove(), 5000)
}

export const watchFlashes = () => {
  const container = document.getElementById("flash-messages")
  if (!container) return
  new MutationObserver((mutations) => {
    for (const { addedNodes } of mutations) addedNodes.forEach(expireRailsAlert)
  }).observe(container, { childList: true })
}
