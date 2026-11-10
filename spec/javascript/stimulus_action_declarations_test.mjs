import assert from "node:assert/strict"
import { readdir, readFile } from "node:fs/promises"
import test from "node:test"

// Controllers whose actions partly live in mixins (Object.assign onto the
// prototype). Each is imported for real, so a mixin that fails to load or
// drops a method shows up here.
const CONTROLLERS = {
  "timeline-feed": "controllers/timeline_feed_controller",
}

const root = new URL("../../", import.meta.url)

async function sources() {
  const entries = await readdir(new URL("app/", root), {
    recursive: true,
    withFileTypes: true,
  })
  const files = entries.filter(
    (entry) => entry.isFile() && /\.(erb|js|rb)$/.test(entry.name),
  )
  return Promise.all(
    files.map((entry) =>
      readFile(`${entry.parentPath ?? entry.path}/${entry.name}`, "utf8"),
    ),
  )
}

const allSources = await sources()

for (const [identifier, path] of Object.entries(CONTROLLERS)) {
  test(`every action bound to ${identifier} exists on the controller`, async () => {
    const pattern = new RegExp(
      `(?<![\\w-])${identifier.replace(/-/g, "\\-")}#([A-Za-z_]\\w*)`,
      "g",
    )
    const bound = new Set()
    for (const source of allSources) {
      for (const match of source.matchAll(pattern)) bound.add(match[1])
    }
    assert.ok(bound.size > 0, `no actions found for ${identifier}`)

    const { default: Controller } = await import(path)
    const missing = [...bound].filter(
      (name) => typeof Controller.prototype[name] !== "function",
    )
    assert.deepEqual(missing, [], `${identifier} lacks: ${missing.join(", ")}`)
  })
}
