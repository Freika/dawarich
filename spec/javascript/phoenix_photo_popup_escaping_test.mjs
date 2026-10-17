import assert from "node:assert/strict"
import test from "node:test"
import { photoPopupHTML } from "../../app-phoenix/assets/js/map/ui/photo_popup.js"

let capturedHTML = ""
function showHostilePopup() {
  capturedHTML = photoPopupHTML(
    {
      geometry: { coordinates: [13.4, 52.5] },
      properties: {
        thumbnail_url: 'x" onerror="alert(4)',
        taken_at: 1_700_000_000,
        filename: '"><script>alert(1)</script>',
        city: "<img src=x onerror=alert(2)>",
        state: null,
        country: null,
        type: "IMAGE",
        source: "<svg onload=alert(3)>",
      },
    },
    { url: 'x" onerror="alert(4)', labels: { "map_info.photo": "Photo" } },
  )

  return capturedHTML
}

test("the photo popup escapes hostile metadata instead of emitting markup", () => {
  const html = showHostilePopup()

  assert.ok(html.length > 0, "expected the popup to be rendered")
  assert.ok(!html.includes("<script>"), "filename injected a script tag")
  assert.ok(!html.includes("<img src=x"), "city injected an img tag")
  assert.ok(!html.includes("<svg onload"), "source injected an svg tag")
  // The hostile thumbnail_url is `x" onerror="alert(4)`: unescaped it closes
  // src and opens a live onerror handler. Escaped, the quote becomes &quot;.
  assert.ok(
    !html.includes('src="x"'),
    "thumbnail_url broke out of the src attribute",
  )
  assert.ok(
    html.includes("&quot;"),
    "quotes in attribute values were not escaped",
  )
})

test("the photo popup still shows the escaped metadata", () => {
  const html = showHostilePopup()

  assert.ok(
    html.includes("&lt;script&gt;"),
    "filename was dropped instead of escaped",
  )
  assert.ok(
    html.includes("&lt;img src=x"),
    "city was dropped instead of escaped",
  )
})
