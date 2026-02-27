import { expect, test } from "@playwright/test"
import { waitForMap } from "../helpers/map.js"
import { closeOnboardingModal } from "../helpers/navigation.js"

test.describe("Routes/Tracks Selector", () => {
  test.beforeEach(async ({ page }) => {
    // Navigate to date with demo data
    await page.goto("/map?start_at=2024-10-15T00:00&end_at=2024-10-15T23:59")
    await closeOnboardingModal(page)
    await waitForMap(page)
    await page.waitForTimeout(2000)
  })

  /**
   * Check if the routes/tracks selector is available
   */
  async function selectorAvailable(page) {
    return await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(
        (c) => c.identifier === "maps",
      )
      return controller?.shouldShowTracksSelector?.() ?? false
    })
  }

  test("should check if routes/tracks selector exists", async ({ page }) => {
    const available = await selectorAvailable(page)

    if (!available) {
      // No tracks data — selector is not expected to show
      const selector = page.locator(".routes-tracks-selector")
      const count = await selector.count()
      expect(count).toBe(0)
      return
    }

    await expect(page.locator(".routes-tracks-selector")).toBeVisible()
  })

  test("should default to Routes mode", async ({ page }) => {
    const available = await selectorAvailable(page)
    if (!available) {
      test.skip()
      return
    }

    const routesChecked = await page.evaluate(() => {
      const radio = document.querySelector(
        '.routes-tracks-selector input[value="routes"]',
      )
      return radio?.checked ?? false
    })
    expect(routesChecked).toBe(true)
  })

  test("should switch to Tracks mode", async ({ page }) => {
    const available = await selectorAvailable(page)
    if (!available) {
      test.skip()
      return
    }

    const tracksRadio = page.locator(
      '.routes-tracks-selector input[value="tracks"]',
    )
    await tracksRadio.click()
    await page.waitForTimeout(300)

    const mode = await page.evaluate(() => localStorage.getItem("mapRouteMode"))
    expect(mode).toBe("tracks")
  })

  test("should persist mode across reload", async ({ page }) => {
    const available = await selectorAvailable(page)
    if (!available) {
      test.skip()
      return
    }

    // Switch to Tracks
    const tracksRadio = page.locator(
      '.routes-tracks-selector input[value="tracks"]',
    )
    await tracksRadio.click()
    await page.waitForTimeout(300)

    // Reload
    await page.reload()
    await closeOnboardingModal(page)
    await waitForMap(page)
    await page.waitForTimeout(2000)

    const stillAvailable = await selectorAvailable(page)
    if (!stillAvailable) {
      test.skip()
      return
    }

    const tracksChecked = await page.evaluate(() => {
      const radio = document.querySelector(
        '.routes-tracks-selector input[value="tracks"]',
      )
      return radio?.checked ?? false
    })
    expect(tracksChecked).toBe(true)
  })

  test("should switch back to Routes", async ({ page }) => {
    const available = await selectorAvailable(page)
    if (!available) {
      test.skip()
      return
    }

    // Switch to Tracks first
    await page.locator('.routes-tracks-selector input[value="tracks"]').click()
    await page.waitForTimeout(300)

    // Switch back to Routes
    await page.locator('.routes-tracks-selector input[value="routes"]').click()
    await page.waitForTimeout(300)

    const mode = await page.evaluate(() => localStorage.getItem("mapRouteMode"))
    expect(mode).toBe("routes")
  })
})
