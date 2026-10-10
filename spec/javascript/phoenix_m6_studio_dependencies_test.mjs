import assert from "node:assert/strict"
import { test } from "node:test"
import { trimOutlierCoords } from "../../app-phoenix/assets/js/poster/dependencies.js"
import { trackBounds, buildPosterStyle, resolveTheme } from "../../app-phoenix/assets/js/video/dependencies.js"

test("poster and video bounds use the integrated geometry and theme modules", () => {
  const coordinates = Array.from({length: 50}, (_,i) => [13+i/1000,52+i/1000]).concat([[100,80]])
  assert.equal(trimOutlierCoords(coordinates).length,50)
  const bounds = trackBounds({type:"FeatureCollection",features:[{type:"Feature",geometry:{type:"LineString",coordinates}}]})
  assert.ok(bounds[1][0] < 14)
  const style = buildPosterStyle({theme: resolveTheme({})})
  assert.equal(style.version,8)
})
