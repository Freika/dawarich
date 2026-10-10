export const meta = (name) =>
  document.querySelector(`meta[name='${name}']`)?.getAttribute("content")

const bridges = new WeakMap()
const islands = new Set()
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

export const railsBridge = (element) => {
  if (bridges.has(element)) return bridges.get(element)
  const bridge = {}
  const controls = [
    ...element.querySelectorAll("button, input, select, textarea"),
  ].map((control) => [control, control.disabled])
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
  },
  updated() {
    this.bridge.ready.then(() => enableForm(this.el))
  },
  destroyed() {
    const bridge = bridges.get(this.el)
    if (!bridge) return
    bridge.ready.then((app) => {
      app.unload(app.controllers.map((controller) => controller.identifier))
      app.stop()
      islands.delete(app)
    })
    bridges.delete(this.el)
  },
}

let loadedMapShell = null
const mapShell = () =>
  import("map_shell").then((shell) => {
    loadedMapShell = shell
    return shell
  })

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

export const stopRailsBridges = () => {
  for (const element of document.querySelectorAll("[phx-hook='RailsStimulus']"))
    RailsStimulus.destroyed.call({ el: element })
  for (const element of document.querySelectorAll("[phx-hook='MapShell']"))
    loadedMapShell?.unmount(element)
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

const watchedFlashes = new WeakSet()

export const watchFlashes = () => {
  const container = document.getElementById("flash-messages")
  if (!container || watchedFlashes.has(container)) return
  watchedFlashes.add(container)
  new MutationObserver((mutations) => {
    for (const { addedNodes } of mutations) addedNodes.forEach(expireRailsAlert)
  }).observe(container, { childList: true })
}
