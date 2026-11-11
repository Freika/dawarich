import assert from "node:assert/strict"
import { readdir, readFile } from "node:fs/promises"
import test from "node:test"

const root = new URL("../../", import.meta.url)

async function filesUnder(dir, extension) {
  const entries = await readdir(new URL(dir, root), {
    recursive: true,
    withFileTypes: true,
  })
  return entries
    .filter((entry) => entry.isFile() && entry.name.endsWith(extension))
    .map((entry) => `${entry.parentPath ?? entry.path}/${entry.name}`)
}

// Every way a view or a script names a maps--maplibre action.
async function boundActionNames() {
  const names = new Set()
  const add = (source, pattern) => {
    for (const match of source.matchAll(pattern)) names.add(match[1])
  }
  for (const path of await filesUnder("app/views/", ".erb")) {
    const source = await readFile(path, "utf8")
    add(source, /maps--maplibre#(\w+)/g)
    // Layer tiles name their action as a bare `action: 'toggleX'` local.
    if (path.includes("/map/maplibre/")) add(source, /\baction: '(\w+)'/g)
    // The map renders the replay panel without its day navigation.
    if (path.endsWith("shared/_replay_panel.html.erb"))
      add(
        source.replace(/<% if show_day_nav %>[\s\S]*?<% end %>/g, ""),
        /<%= stimulus %>#(\w+)/g,
      )
  }
  for (const path of await filesUnder("app/javascript/", ".js")) {
    const source = await readFile(path, "utf8")
    add(source, /maps--maplibre#(\w+)/g)
    if (source.includes("maps--maplibre#${action.handler}"))
      add(source, /handler: "(\w+)"/g)
  }
  return names
}

const source = (
  await readFile(
    new URL("app/javascript/controllers/maps/maplibre_controller.js", root),
    "utf8",
  )
).replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
const { default: MapController } = await import(
  `data:text/javascript;base64,${Buffer.from(`class Controller {}\n${source}`).toString("base64")}`
)

test("every action the views bind exists on the maps--maplibre controller", async () => {
  const bound = await boundActionNames()
  assert.ok(bound.size > 50, `found only ${bound.size} bound actions`)
  const missing = [...bound].filter(
    (name) => typeof MapController.prototype[name] !== "function",
  )
  assert.deepEqual(missing, [], `Unbound actions: ${missing.join(", ")}`)
})
