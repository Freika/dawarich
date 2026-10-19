import assert from "node:assert/strict"
import test from "node:test"
import { mapTranslate } from "../../assets/js/map/ui/translate.js"

test("count bindings pick the singular label when one is provided", () => {
  const translate = mapTranslate(() => ({
    uiLabels: {
      "selection.delete_points": "Delete {count} Points",
      "selection.delete_points.one": "Delete 1 Point",
    },
  }))
  assert.equal(translate("selection.delete_points", { count: 1 }), "Delete 1 Point")
  assert.equal(translate("selection.delete_points", { count: 3 }), "Delete 3 Points")
  assert.equal(translate("missing.key"), "missing.key")
})
