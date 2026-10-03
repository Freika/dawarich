// FIXME: es-module-shim won't shim the dynamic import without this explicit import
import "@hotwired/stimulus"

export function registerControllersFrom(under, application) {
  const paths = Object.keys(parseImportmapJson())
    .filter(path => path.match(new RegExp(`^${under}/.*_controller$`)))

  paths.forEach(path => registerControllerFromPath(path, under, application))
}

export function parseImportmapJson() {
  return JSON.parse(document.querySelector("script[type=importmap]").text).imports
}

function registerControllerFromPath(path, under, application) {
  const name = path
    .replace(new RegExp(`^${under}/`), "")
    .replace("_controller", "")
    .replace(/\//g, "--")
    .replace(/_/g, "-")

  import(path)
    .then(module => application.register(name, module.default))
    .catch(error => console.error(`Failed to register controller: ${name} (${path})`, error))
}

console.warn("stimulus-importmap-autoload.js has been deprecated in favor of stimulus-loading.js")
