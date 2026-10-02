import "@hotwired/turbo-rails"
import { Application } from "@hotwired/stimulus"
import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"
import { appendRailsFlash } from "rails_bridge"

window.Turbo.session.drive = false

const applications = new WeakMap()
const portals = new WeakMap()

class MapApplication extends Application {
  constructor(element, family) {
    super(element)
    this.family = family
    this.identifiers = new Set()
    this.disposed = false
    family.add(this)
  }

  register(identifier, controller) {
    if (this.disposed) return
    this.identifiers.add(identifier)
    super.register(identifier, controller)
  }

  dispose() {
    if (this.disposed) return
    this.disposed = true
    this.unload([...this.identifiers])
    this.identifiers.clear()
    this.stop()
  }

  getControllerForElementAndIdentifier(element, identifier) {
    for (const app of this.family) {
      const controller =
        Application.prototype.getControllerForElementAndIdentifier.call(
          app,
          element,
          identifier,
        )
      if (controller) return controller
    }
    return null
  }
}
let view = null

const controllerPath = (identifier) =>
  `controllers/${identifier.replace(/--/g, "/").replace(/-/g, "_")}_controller`

const ownIdentifiers = (element) =>
  (element.getAttribute("data-controller") || "")
    .split(/\s+/)
    .filter((identifier) => identifier !== "")

const start = (element, family) => {
  const application = new MapApplication(element, family)
  application.start().then(() => {
    if (application.disposed) application.stop()
  })
  applications.set(element, application)
  for (const identifier of ownIdentifiers(element)) {
    import(controllerPath(identifier)).then((module) =>
      application.register(identifier, module.default),
    )
  }
  lazyLoadControllersFrom("controllers", application, element)
  return application
}

export const mount = (element, hook = null) => {
  if (!element.isConnected) return null
  if (hook) view = hook
  if (applications.has(element)) return applications.get(element)
  const family = new Set()
  const studios =
    element.id === "map-shell" || element.id === "trip-shell"
      ? [...element.querySelectorAll("#poster-studio, #video-studio")]
      : []
  for (const studio of studios) {
    studio.setAttribute("data-turbo", "true")
    document.body.appendChild(studio)
  }
  const application = start(element, family)
  for (const studio of studios) start(studio, family)
  portals.set(element, studios)
  if (element.id === "map-shell" || element.id === "trip-shell") window.Stimulus = application
  return application
}

export const join = (hook) => {
  view = hook
}

export const leave = (hook) => {
  if (view === hook) view = null
}

export const unmount = (element) => {
  for (const studio of portals.get(element) || []) {
    applications.get(studio)?.dispose()
    applications.delete(studio)
    studio.remove()
  }
  portals.delete(element)
  applications.get(element)?.dispose()
  applications.get(element)?.family.clear()
  applications.delete(element)
  if (view?.el === element) view = null
}

document.addEventListener("turbo:before-stream-render", (event) => {
  const stream = event.target
  if (stream.getAttribute("target") !== "flash-messages") return
  const content = stream.querySelector("template")?.content
  if (!content) return
  event.preventDefault()
  if (!view) return appendRailsFlash(content)
  const alert = content.querySelector("[role='alert']")
  view.pushEvent("rails_flash", {
    type: alert?.classList.contains("alert-error") ? "error" : "success",
    message: alert?.querySelector("span")?.textContent || "",
  })
})
