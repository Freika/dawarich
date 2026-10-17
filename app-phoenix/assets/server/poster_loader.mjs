import { createRequire } from "node:module"
import path from "node:path"
import { fileURLToPath, pathToFileURL } from "node:url"

const rendererDir = path.dirname(fileURLToPath(import.meta.url))
const browser = path.join(rendererDir, "browser")
const rendererRequire = createRequire(path.join(rendererDir, "render.mjs"))

export async function resolve(specifier, context, nextResolve) {
  if (/^poster_studio\//.test(specifier)) {
    const file = path.join(
      browser,
      `${specifier.replace(/^poster_studio\//, "").replace(/\.js$/, "")}.js`,
    )
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
