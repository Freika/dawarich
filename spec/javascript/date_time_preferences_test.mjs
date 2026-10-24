import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL("../../app/javascript/i18n.js", import.meta.url),
  "utf8",
)

let copy = 0
async function loadWith({ lang = "en", preferences, translations = {} }) {
  copy += 1
  globalThis.document = {
    documentElement: { lang },
    getElementById: () => ({ textContent: JSON.stringify(translations) }),
    querySelector: (selector) =>
      selector === 'meta[name="date-time-preferences"]' && preferences
        ? { content: JSON.stringify(preferences) }
        : null,
  }
  return import(
    `data:text/javascript;base64,${Buffer.from(`${source}\n// copy ${copy}`).toString("base64")}`
  )
}

const clock = (clock12h, am, pm) => ({
  date_time_preferences: { clock_12h: clock12h, meridiem: { am, pm } },
})
const afternoon = new Date(Date.UTC(2026, 9, 24, 14, 5, 30))
const morning = new Date(Date.UTC(2026, 2, 5, 9, 7, 4))

test("renders full dates with each preset", async () => {
  try {
    const cases = {
      "dd.mm.yyyy": "24.10.2026",
      "dd/mm/yyyy": "24/10/2026",
      "mm/dd/yyyy": "10/24/2026",
      "yyyy-mm-dd": "2026-10-24",
    }
    for (const [dateFormat, expected] of Object.entries(cases)) {
      const { formatDate } = await loadWith({
        preferences: { date_format: dateFormat },
      })
      assert.equal(formatDate(afternoon, { timeZone: "UTC" }), expected)
    }
  } finally {
    delete globalThis.document
  }
})

test("renders auto dates with the interface locale", async () => {
  try {
    const { formatDate } = await loadWith({
      preferences: { date_format: "auto" },
    })
    assert.equal(formatDate(afternoon, { timeZone: "UTC" }), "Oct 24, 2026")

    const withoutMeta = await loadWith({})
    assert.equal(
      withoutMeta.formatDate(morning, { timeZone: "UTC" }),
      "Mar 5, 2026",
    )
  } finally {
    delete globalThis.document
  }
})

test("renders 24h times for auto and 24h", async () => {
  try {
    for (const timeFormat of ["auto", "24h"]) {
      const { formatTime } = await loadWith({
        preferences: { time_format: timeFormat },
      })
      assert.equal(formatTime(afternoon, { timeZone: "UTC" }), "14:05")
      assert.equal(
        formatTime(morning, { timeZone: "UTC", seconds: true }),
        "09:07:04",
      )
    }
  } finally {
    delete globalThis.document
  }
})

test("renders 12h times with the same locale strings as the server", async () => {
  try {
    const en = await loadWith({
      preferences: { time_format: "12h" },
      translations: clock("%{time} %{meridiem}", "AM", "PM"),
    })
    assert.equal(en.formatTime(afternoon, { timeZone: "UTC" }), "2:05 PM")
    assert.equal(en.formatTime(morning, { timeZone: "UTC" }), "9:07 AM")
    assert.equal(
      en.formatTime(afternoon, { timeZone: "UTC", seconds: true }),
      "2:05:30 PM",
    )

    const zh = await loadWith({
      lang: "zh",
      preferences: { time_format: "12h" },
      translations: clock("%{meridiem}%{time}", "上午", "下午"),
    })
    assert.equal(zh.formatTime(afternoon, { timeZone: "UTC" }), "下午2:05")

    const es = await loadWith({
      lang: "es",
      preferences: { time_format: "12h" },
      translations: clock("%{time} %{meridiem}", "a. m.", "p. m."),
    })
    assert.equal(es.formatTime(afternoon, { timeZone: "UTC" }), "2:05 p. m.")
  } finally {
    delete globalThis.document
  }
})

test("renders datetimes as date and time", async () => {
  try {
    const { formatDateTime } = await loadWith({
      preferences: { date_format: "dd.mm.yyyy", time_format: "12h" },
      translations: clock("%{time} %{meridiem}", "AM", "PM"),
    })
    assert.equal(
      formatDateTime(afternoon, { timeZone: "UTC" }),
      "24.10.2026, 2:05 PM",
    )
  } finally {
    delete globalThis.document
  }
})

test("reads the preferences on every call", async () => {
  try {
    const { formatDate } = await loadWith({
      preferences: { date_format: "dd.mm.yyyy" },
    })
    assert.equal(formatDate(afternoon, { timeZone: "UTC" }), "24.10.2026")

    globalThis.document.querySelector = () => ({
      content: JSON.stringify({ date_format: "yyyy-mm-dd" }),
    })
    assert.equal(formatDate(afternoon, { timeZone: "UTC" }), "2026-10-24")
  } finally {
    delete globalThis.document
  }
})

test("returns the first day of week as a JS weekday number", async () => {
  try {
    assert.equal(
      (
        await loadWith({ preferences: { first_day_of_week: "sunday" } })
      ).firstDayOfWeek(),
      0,
    )
    assert.equal(
      (
        await loadWith({ preferences: { first_day_of_week: "monday" } })
      ).firstDayOfWeek(),
      1,
    )
    assert.equal((await loadWith({})).firstDayOfWeek(), 1)
  } finally {
    delete globalThis.document
  }
})
