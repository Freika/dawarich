import { expect, test } from "@playwright/test"

const VIEWPORTS = [
  { width: 390, height: 844 },
  { width: 640, height: 900 },
  { width: 1440, height: 900 },
]
const HEADINGS = { en: "Stay up to date?", de: "Aktuell bleiben?" }

for (const viewport of VIEWPORTS) {
  for (const [locale, heading] of Object.entries(HEADINGS)) {
    test(`the What's New opt-in card stays on screen at ${viewport.width}px in ${locale}`, async ({
      page,
    }) => {
      await page.setViewportSize(viewport)
      await page.goto(`/settings/general?locale=${locale}`)

      const card = page.locator(".card", {
        has: page.getByRole("heading", { name: heading }),
      })
      await expect(card).toBeVisible()
      const box = await card.boundingBox()

      expect(box.x).toBeGreaterThanOrEqual(0)
      expect(box.x + box.width).toBeLessThanOrEqual(viewport.width)
      await expect(
        card.getByRole("button", { name: /./ }).first(),
      ).toBeInViewport({ ratio: 1 })
    })
  }
}

test.afterAll(async ({ browser }) => {
  const page = await browser.newPage({
    storageState: "e2e/temp/.auth/user.json",
  })
  await page.goto("/settings/general?locale=en")
  await page.close()
})
