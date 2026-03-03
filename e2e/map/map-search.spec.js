import { expect, test } from "@playwright/test"
import { waitForMap } from "../helpers/map.js"
import { navigateToMap } from "../helpers/navigation.js"

test.describe("Map Search", () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMap(page)
    await waitForMap(page)
  })

  test("should display search toggle button", async ({ page }) => {
    await expect(page.locator("#location-search-toggle")).toBeVisible()
  })

  test("should open search bar when clicking search button", async ({
    page,
  }) => {
    await page.locator("#location-search-toggle").click()
    await page.waitForTimeout(300)

    const container = page.locator("#location-search-container")
    await expect(container).toBeVisible()
    await expect(container).not.toHaveClass(/hidden/)
  })

  test("should focus search input when search bar opens", async ({ page }) => {
    await page.locator("#location-search-toggle").click()
    await page.waitForTimeout(300)

    const isFocused = await page.evaluate(() => {
      return document.activeElement?.id === "location-search-input"
    })
    expect(isFocused).toBe(true)
  })

  test("should close search bar when clicking close button", async ({
    page,
  }) => {
    // Open
    await page.locator("#location-search-toggle").click()
    await page.waitForTimeout(300)

    // Close
    await page.locator("#location-search-close").click()
    await page.waitForTimeout(300)

    await expect(page.locator("#location-search-container")).toHaveClass(
      /hidden/,
    )
  })

  test("should close search bar on Escape key", async ({ page }) => {
    // Open
    await page.locator("#location-search-toggle").click()
    await page.waitForTimeout(300)

    // Press Escape
    await page.keyboard.press("Escape")
    await page.waitForTimeout(300)

    await expect(page.locator("#location-search-container")).toHaveClass(
      /hidden/,
    )
  })

  test("should show search input with placeholder", async ({ page }) => {
    await page.locator("#location-search-toggle").click()
    await page.waitForTimeout(300)

    const placeholder = await page
      .locator("#location-search-input")
      .getAttribute("placeholder")
    expect(placeholder).toBe("Search locations...")
  })

  test("should have results panels initially hidden", async ({ page }) => {
    await page.locator("#location-search-toggle").click()
    await page.waitForTimeout(300)

    await expect(
      page.locator("#location-search-suggestions-panel"),
    ).toHaveClass(/hidden/)
    await expect(page.locator("#location-search-results-panel")).toHaveClass(
      /hidden/,
    )
  })
})
