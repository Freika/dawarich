import { expect, test } from "@playwright/test"

test.describe.configure({ mode: "serial" })

async function savePreferences(page, { date, time, week }) {
  await page.goto("/settings/general")
  await page.getByTestId("date-format-select").selectOption(date)
  await page.getByTestId("time-format-select").selectOption(time)
  await page.getByTestId("first-day-of-week-select").selectOption(week)
  await page.getByRole("button", { name: "Save changes" }).click()
  await expect(page.getByText("Settings updated")).toBeVisible()
}

async function weekdayHeader(page) {
  const response = await page.request.get(
    "/map/timeline_feeds/calendar?month=2026-10",
  )
  const html = await response.text()
  const header = html.slice(html.indexOf("grid-cols-7"))
  return [...header.matchAll(/<div class="text-center">([^<]*)<\/div>/g)]
    .slice(0, 7)
    .map((match) => match[1])
}

const EXPORT_NAME = "export_from_2026-10-01_to_2026-10-02.json"

async function csrfToken(page) {
  return page.locator('meta[name="csrf-token"]').getAttribute("content")
}

async function createExport(page) {
  const response = await page.request.post("/exports", {
    form: {
      authenticity_token: await csrfToken(page),
      start_at: "2026-10-01",
      end_at: "2026-10-02",
      file_format: "json",
    },
  })
  expect(response.ok()).toBe(true)
}

async function deleteExports(page) {
  await page.goto("/exports")
  const ids = await page
    .locator(`tr[id^="export_"]:has-text("${EXPORT_NAME}")`)
    .evaluateAll((rows) => rows.map((row) => row.id.replace("export_", "")))
  const token = await csrfToken(page)
  for (const id of ids) {
    await page.request.delete(`/exports/${id}`, {
      form: { authenticity_token: token },
    })
  }
}

function exportRow(page) {
  return page.locator(`tr[id^="export_"]:has-text("${EXPORT_NAME}")`).first()
}

test.afterAll(async ({ browser }) => {
  const page = await browser.newPage({
    storageState: "e2e/temp/.auth/user.json",
  })
  await savePreferences(page, { date: "auto", time: "auto", week: "monday" })
  await page.close()
})

test("saved preferences change server dates, JavaScript dates and the calendar", async ({
  page,
}) => {
  await savePreferences(page, {
    date: "yyyy-mm-dd",
    time: "12h",
    week: "sunday",
  })

  await page.goto("/insights?year=all")
  await expect(page.getByTestId("insights-year-card").first()).toContainText(
    /\d{4}-\d{2}-\d{2}/,
  )

  const formatted = await page.evaluate(async () => {
    const i18n = await import("i18n")
    const sample = new Date(2026, 9, 24, 14, 5)
    return {
      date: i18n.formatDate(sample),
      time: i18n.formatTime(sample),
      firstDay: i18n.firstDayOfWeek(),
    }
  })
  expect(formatted).toEqual({
    date: "2026-10-24",
    time: "2:05 PM",
    firstDay: 0,
  })

  expect(await weekdayHeader(page)).toEqual(["S", "M", "T", "W", "T", "F", "S"])
})

test("a Turbo visit picks up preferences changed while the page was open", async ({
  page,
}) => {
  await savePreferences(page, {
    date: "dd.mm.yyyy",
    time: "24h",
    week: "monday",
  })
  try {
    await createExport(page)
    const before = await page.evaluate(async () =>
      (await import("i18n")).formatDateTime(new Date(2026, 9, 24, 14, 5)),
    )
    expect(before).toBe("24.10.2026, 14:05")

    const response = await page.request.patch("/settings/general", {
      maxRedirects: 0,
      form: {
        authenticity_token: await csrfToken(page),
        date_format: "yyyy-mm-dd",
        time_format: "12h",
      },
    })
    expect(response.status()).toBe(302)

    await page.evaluate(() => window.Turbo.visit("/exports"))
    await expect(page).toHaveURL(/\/exports/)
    await expect(exportRow(page)).toContainText(
      /\d{4}-\d{2}-\d{2}, \d{1,2}:\d{2} (AM|PM)/,
    )
    const after = await page.evaluate(async () =>
      (await import("i18n")).formatDateTime(new Date(2026, 9, 24, 14, 5)),
    )
    expect(after).toBe("2026-10-24, 2:05 PM")

    await page.goto("/map/v2")
    const label = page.locator('[data-map-controls-target="mobileLabel"]')
    await expect(label).toHaveText(/^\d{4}-\d{2}-\d{2}$/)
    await page.evaluate(() =>
      document.dispatchEvent(
        new CustomEvent("timeline-feed:date-navigated", {
          detail: { startAt: "2026-03-05T00:00", endAt: "2026-03-05T23:59" },
        }),
      ),
    )
    await expect(label).toHaveText("2026-03-05")
  } finally {
    await deleteExports(page)
  }
})

test("German 12h pages do not scroll sideways on a phone", async ({ page }) => {
  await savePreferences(page, {
    date: "dd.mm.yyyy",
    time: "12h",
    week: "monday",
  })
  await page.setViewportSize({ width: 390, height: 844 })
  const sidewaysOverflow = () =>
    page.evaluate(
      () =>
        document.documentElement.scrollWidth -
        document.documentElement.clientWidth,
    )

  try {
    await createExport(page)

    await page.goto("/settings/general?locale=de")
    await page.getByTestId("date-format-select").scrollIntoViewIfNeeded()
    expect(await sidewaysOverflow()).toBeLessThanOrEqual(0)
    await page.screenshot({
      path: "test-results/date-time-settings-de-390.png",
    })

    await page.goto("/exports?locale=de")
    await expect(exportRow(page)).toContainText(
      /\d{2}\.\d{2}\.\d{4}, \d{1,2}:\d{2} (AM|PM)/,
    )
    expect(await sidewaysOverflow()).toBeLessThanOrEqual(0)
    await page.screenshot({ path: "test-results/date-time-exports-de-390.png" })

    await page.goto("/map/v2?locale=de")
    await expect(
      page.locator('[data-map-controls-target="mobileLabel"]'),
    ).toHaveText(/^\d{2}\.\d{2}\.\d{4}$/)
    expect(await sidewaysOverflow()).toBeLessThanOrEqual(0)
  } finally {
    await page.goto("/settings/general?locale=en")
    await deleteExports(page)
  }
})
