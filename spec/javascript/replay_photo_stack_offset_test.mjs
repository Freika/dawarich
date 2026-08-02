import assert from "node:assert/strict"
import { test } from "node:test"

import { stackLeftOffset } from "../../app/javascript/maps_maplibre/components/replay_photo_stack_offset.js"

const container = { left: 0, top: 0 }

test("falls back to the base inset when no button cluster is present", () => {
  // The trip map renders no button cluster, so the stack must stay in the corner.
  assert.equal(
    stackLeftOffset({ container, cluster: null, base: 16, gap: 10 }),
    16,
  )
})

test("clears the cluster when one is present", () => {
  const cluster = { left: 12, right: 66, width: 54, height: 300 }

  assert.equal(stackLeftOffset({ container, cluster, base: 16, gap: 10 }), 76)
})

test("follows the cluster when the settings panel shifts it right", () => {
  const cluster = { left: 492, right: 546, width: 54, height: 300 }

  assert.equal(stackLeftOffset({ container, cluster, base: 16, gap: 10 }), 556)
})

test("measures relative to the map container, not the viewport", () => {
  const offsetContainer = { left: 200, top: 0 }
  const cluster = { left: 212, right: 266, width: 54, height: 300 }

  assert.equal(
    stackLeftOffset({ container: offsetContainer, cluster, base: 16, gap: 10 }),
    76,
  )
})

test("ignores a cluster that is present but not rendered", () => {
  // A hidden cluster reports a zero-size rect; offsetting past it would push the
  // stack toward the middle of an otherwise empty map.
  const hidden = { left: 0, right: 0, width: 0, height: 0 }

  assert.equal(
    stackLeftOffset({ container, cluster: hidden, base: 16, gap: 10 }),
    16,
  )
})

test("never returns less than the base inset", () => {
  const cluster = { left: -80, right: -20, width: 60, height: 300 }

  assert.equal(stackLeftOffset({ container, cluster, base: 16, gap: 10 }), 16)
})
