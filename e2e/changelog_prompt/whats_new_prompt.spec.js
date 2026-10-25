import { expect, test } from "@playwright/test"

const VIEWPORTS = [
  { width: 390, height: 844 },
  { width: 639, height: 900 },
  { width: 640, height: 900 },
  { width: 1440, height: 900 },
  { width: 568, height: 320 },
  { width: 320, height: 420 },
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
      expect(box.y + box.height).toBeLessThanOrEqual(viewport.height)
      if (viewport.width >= 640) expect(box.width).toBeCloseTo(288, 0)
      await expect(card.getByRole("heading", { name: heading })).toBeInViewport(
        {
          ratio: 1,
        },
      )
      for (const button of await card.getByRole("button").all()) {
        await button.scrollIntoViewIfNeeded()
        await expect(button).toBeInViewport({ ratio: 1 })
      }
    })
  }
}
