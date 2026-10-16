import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import { fileURLToPath } from "node:url"
import test from "node:test"
import { createHostEditing } from "../../assets/js/map/edit/host.js"
import { fixture } from "../../../spec/javascript/support/native_m6_host_fixture.mjs"

test("host move completion keeps reconciliation history and moved-point effects without shadowed callbacks", async () => {
  const build = spawnSync(fileURLToPath(new URL(`../../_build/esbuild-${process.platform}-${process.arch}`, import.meta.url)), [
    fileURLToPath(new URL("../../assets/js/map/edit/host.js", import.meta.url)),
    "--log-override:duplicate-object-key=error", "--outfile=/dev/null",
  ], { encoding: "utf8" })
  assert.equal(build.status, 0, build.stderr)
  const f = fixture({ editEnabled: true })
  const cleanups = [], moved = []
  const error = { textContent: "previous failure" }
  const track = { type: "Feature", properties: { id: 9, revision: 1 }, geometry: { type: "LineString", coordinates: [[13, 52], [14, 53]] } }
  let reads = 0
  f.reader.read = async () => { reads++; return { data: track } }
  const editing = createHostEditing({
    map: f.map, reader: f.reader, pushEvent() {},
    lifetime: { own: fn => cleanups.push(fn) },
    getConfig: () => f.owner.config,
    layers: { points: { refresh() {} }, tracks: { refresh() {} } },
    document: f.element.ownerDocument,
    root: { querySelector: () => error },
    onMoved: response => moved.push(response),
  })
  try {
    const editor = editing.editor
    editor.trackId = 9
    editor.data = { type: "FeatureCollection", features: [track] }
    const response = { track, revision: { track: 1 } }
    editor.onMoved(response)
    assert.deepEqual(moved, [response])
    assert.equal(error.textContent, "")
    await editing.reconcile({ kinds: ["map_edits"] })
    assert.equal(reads, 1)
    assert.ok(editor.data)
  } finally {
    for (const cleanup of cleanups.reverse()) cleanup()
    f.owner.destroy()
  }
})
