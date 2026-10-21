import { Application } from "@hotwired/stimulus"

const application = Application.start()
const { controllerAttribute } = application.schema
const registeredControllers = {}

function autoloadControllersWithin(element) {
  queryControllerNamesWithin(element).forEach(loadController)
}

function queryControllerNamesWithin(element) {
  return Array.from(element.querySelectorAll(`[${controllerAttribute}]`)).map(extractControllerNamesFrom).flat()
}

function extractControllerNamesFrom(element) {
  return element.getAttribute(controllerAttribute).split(/\s+/).filter(content => content.length)
}

function loadController(name) {
  import(controllerFilename(name))
    .then(module => registerController(name, module))
    .catch(error => console.error(`Failed to autoload controller: ${name}`, error))
}

function controllerFilename(name) {
  return `controllers/${name.replace(/--/g, "/").replace(/-/g, "_")}_controller`
}

function registerController(name, module) {
  if (name in registeredControllers) return

  application.register(name, module.default)
  registeredControllers[name] = true
}


new MutationObserver((mutationsList) => {
  for (const { attributeName, target, type } of mutationsList) {
    switch (type) {
      case "attributes": {
        if (attributeName == controllerAttribute && target.getAttribute(controllerAttribute)) {
          extractControllerNamesFrom(target).forEach(loadController)
        }
      }
      case "childList": {
        autoloadControllersWithin(target)
      }
    }
  }
}).observe(document, { attributeFilter: [controllerAttribute], subtree: true, childList: true })

autoloadControllersWithin(document)

console.warn("stimulus-autoload.js has been deprecated in favor of stimulus-loading.js")
