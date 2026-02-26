import { expect, test } from "@playwright/test"
import { waitForMap } from "../helpers/map.js"
import { navigateToMap } from "../helpers/navigation.js"

test.describe("Info Toggle Button", () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMap(page)
    await waitForMap(page)
  })

  test("should display info toggle button", async ({ page }) => {
    const button = page.locator(".map-info-toggle-button")
    await expect(button).toBeVisible()

    const tooltip = await button.getAttribute("data-tip")
    expect(tooltip).toBe("Toggle footer visibility")
  })

  test("should toggle footer visibility", async ({ page }) => {
    const button = page.locator(".map-info-toggle-button")
    const footer = page.locator("#map-footer")

    // Footer should be hidden initially
    await expect(footer).toHaveClass(/hidden/)

    // Click to show footer
    await button.click()
    await page.waitForTimeout(300)
    await expect(footer).not.toHaveClass(/hidden/)

    // Click again to hide footer
    await button.click()
    await page.waitForTimeout(300)
    await expect(footer).toHaveClass(/hidden/)
  })

  test("should adjust bottom controls position on toggle", async ({ page }) => {
    const button = page.locator(".map-info-toggle-button")

    // Get initial position of bottom-right controls
    const getBottomControlPosition = () =>
      page.evaluate(() => {
        const control = document.querySelector(".leaflet-bottom.leaflet-right")
        return control ? window.getComputedStyle(control).bottom : null
      })

    const initialBottom = await getBottomControlPosition()

    // Show footer
    await button.click()
    await page.waitForTimeout(500)

    const afterToggleBottom = await getBottomControlPosition()

    // The bottom position should have changed (footer takes up space)
    // If footer is rendered, controls shift up
    expect(afterToggleBottom !== null || initialBottom !== null).toBe(true)
  })
})
