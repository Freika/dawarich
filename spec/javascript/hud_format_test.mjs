import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const read = (path) =>
  readFile(new URL(`../../app/javascript/${path}`, import.meta.url), "utf8")
const bundle = [await read("i18n.js"), await read("video_studio/hud_format.js")]
  .join("\n")
  .replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
  .replace(/^export /gm, "")
  .concat("\nexport { formatClockDate, formatDateRange }\n")
const { formatClockDate, formatDateRange } = await import(
  `data:text/javascript;base64,${Buffer.from(bundle).toString("base64")}`
)

const afternoon = new Date(2026, 9, 24, 14, 5).getTime()
const later = new Date(2026, 9, 26, 9, 0).getTime()

function withPreferences(preferences, translations, fn) {
  globalThis.document = {
    documentElement: { lang: "en" },
    getElementById: () => ({ textContent: JSON.stringify(translations) }),
    querySelector: () => ({ content: JSON.stringify(preferences) }),
  }
  try {
    return fn()
  } finally {
    delete globalThis.document
  }
}

test("keeps the HUD design for automatic dates", () => {
  assert.equal(formatClockDate(afternoon), "24 OCT 2026 · 14:05")
  assert.equal(formatDateRange(afternoon, later), "24 — 26 OCT 2026")
})

test("uses the date preset and 12h clock when chosen", () => {
  const translations = {
    date_time_preferences: {
      clock_12h: "%{time} %{meridiem}",
      meridiem: { am: "AM", pm: "PM" },
    },
  }
  withPreferences(
    { date_format: "yyyy-mm-dd", time_format: "12h" },
    translations,
    () => {
      assert.equal(formatClockDate(afternoon), "2026-10-24 · 2:05 PM")
      assert.equal(formatDateRange(afternoon, later), "2026-10-24 — 2026-10-26")
    },
  )
})
