import { expect, test } from "@playwright/test"
import { waitForMap } from "../helpers/map.js"
import { closeOnboardingModal, navigateToMap } from "../helpers/navigation.js"

test.describe("Stats Display", () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMap(page)
    await waitForMap(page)
  })

  test("should display stats control on map", async ({ page }) => {
    await expect(page.locator(".leaflet-control-stats")).toBeVisible()
  })

  test("should show distance and points count", async ({ page }) => {
    const statsText = await page.locator(".leaflet-control-stats").textContent()
    expect(statsText).toMatch(/\d+\s*(km|mi)\s*\|\s*\d+\s*points/)
  })

  test("should display scale control", async ({ page }) => {
    await expect(page.locator(".leaflet-control-scale")).toBeVisible()
  })

  test("should update stats after navigating to date with data", async ({
    page,
  }) => {
    // Navigate to October 15, 2024 (demo data date)
    await page.goto("/map?start_at=2024-10-15T00:00&end_at=2024-10-15T23:59")
    await closeOnboardingModal(page)
    await waitForMap(page)
    await page.waitForTimeout(2000)

    const statsText = await page.locator(".leaflet-control-stats").textContent()
    // Should show some distance (non-zero)
    const distanceMatch = statsText.match(/([\d.]+)\s*(km|mi)/)
    expect(distanceMatch).toBeTruthy()

    const pointsMatch = statsText.match(/(\d+)\s*points/)
    expect(pointsMatch).toBeTruthy()
    expect(parseInt(pointsMatch[1], 10)).toBeGreaterThan(0)
  })
})
