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

test("JavaScript follows a preference change after a Turbo visit", async ({
  page,
}) => {
  await savePreferences(page, {
    date: "dd.mm.yyyy",
    time: "24h",
    week: "monday",
  })
  await page.goto("/settings/general")
  await page.getByTestId("date-format-select").selectOption("mm/dd/yyyy")
  await page.getByRole("button", { name: "Save changes" }).click()
  await expect(page.getByText("Settings updated")).toBeVisible()

  await page.locator('a[href$="/insights"]:visible').first().click()
  await expect(page).toHaveURL(/\/insights/)

  const date = await page.evaluate(async () =>
    (await import("i18n")).formatDate(new Date(2026, 9, 24)),
  )
  expect(date).toBe("10/24/2026")
})

test("the settings section does not scroll sideways on a phone in German", async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto("/settings/general?locale=de")
  await page.getByTestId("date-format-select").scrollIntoViewIfNeeded()

  const overflow = await page.evaluate(
    () =>
      document.documentElement.scrollWidth -
      document.documentElement.clientWidth,
  )
  expect(overflow).toBeLessThanOrEqual(0)
  await page.screenshot({ path: "test-results/date-time-settings-de-390.png" })
  await page.goto("/settings/general?locale=en")
})
