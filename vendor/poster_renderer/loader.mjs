// Resolves the app's importmap-style bare specifiers ("poster_studio/...")
// to files under app/javascript, so the renderer can import the exact same
// modules the browser runs. npm packages the app pins via importmap (e.g.
// fflate) resolve from the renderer's own node_modules as a fallback.
// Registered via --import in register.mjs.
import { createRequire } from "node:module"
import path from "node:path"
import { fileURLToPath, pathToFileURL } from "node:url"

const rendererDir = path.dirname(fileURLToPath(import.meta.url))
const appJavascript = path.resolve(rendererDir, "../../app/javascript")
const rendererRequire = createRequire(path.join(rendererDir, "render.mjs"))

export async function resolve(specifier, context, nextResolve) {
  if (/^(poster_studio|maps_maplibre)\//.test(specifier)) {
    const file = path.join(appJavascript, `${specifier.replace(/\.js$/, "")}.js`)
    return { url: pathToFileURL(file).href, shortCircuit: true }
  }
  try {
    return await nextResolve(specifier, context)
  } catch (error) {
    if (!specifier.startsWith(".") && !specifier.startsWith("/")) {
      return {
        url: pathToFileURL(rendererRequire.resolve(specifier)).href,
        shortCircuit: true,
      }
    }
    throw error
  }
}
