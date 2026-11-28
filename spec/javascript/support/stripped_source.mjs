import { readFile } from "node:fs/promises"
import path from "node:path"
import { fileURLToPath } from "node:url"

const appJavascript = fileURLToPath(
  new URL("../../../app/javascript/", import.meta.url),
)
const IMPORT = /^import\s+([\s\S]*?)\s+from\s+"([^"]+)"\n/gm

/**
 * Source of an app module with its imports removed, for tests that supply
 * their own stubs. Mixins the module applies with
 * `Object.assign(Class.prototype, ...)` are inlined first (also without
 * imports), so the result does not depend on how a controller is split.
 *
 * @param {string} relativePath path under app/javascript, e.g.
 *   "controllers/video_studio_controller.js"
 * @param {{ inline?: string[] }} options other modules under app/javascript
 *   to inline first, the same way (for imported classes, not mixins)
 */
export async function strippedSource(relativePath, { inline = [] } = {}) {
  const file = path.join(appJavascript, relativePath)
  const source = await readFile(file, "utf8")

  const importPaths = new Map()
  for (const [, clause, specifier] of source.matchAll(IMPORT)) {
    for (const name of clause.replace(/[{}]/g, "").split(",")) {
      const local = name
        .trim()
        .split(/\s+as\s+/)
        .pop()
      if (local) importPaths.set(local, specifier)
    }
  }

  const mixins = []
  for (const other of inline) {
    mixins.push(
      (await readFile(path.join(appJavascript, other), "utf8"))
        .replace(IMPORT, "")
        .replace(/^export /gm, ""),
    )
  }
  for (const [, list] of source.matchAll(
    /^Object\.assign\(\s*\w+\.prototype,([\s\S]*?)\)$/gm,
  )) {
    for (const name of list
      .split(",")
      .map((n) => n.trim())
      .filter(Boolean)) {
      const specifier = importPaths.get(name)
      if (!specifier) continue
      const mixinFile = specifier.startsWith(".")
        ? path.resolve(path.dirname(file), `${specifier}.js`)
        : path.join(appJavascript, `${specifier}.js`)
      mixins.push(
        (await readFile(mixinFile, "utf8"))
          .replace(IMPORT, "")
          .replace(/^export /gm, ""),
      )
    }
  }

  return [...mixins, source.replace(IMPORT, "")].join("\n")
}
