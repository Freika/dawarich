import { expect, test } from "@playwright/test"
import { openSettingsPanel, waitForMap } from "../helpers/map.js"
import { navigateToMap } from "../helpers/navigation.js"

test.describe("Settings Panel", () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMap(page)
    await waitForMap(page)
  })

  test("should display settings gear button", async ({ page }) => {
    await expect(page.locator(".map-settings-button")).toBeVisible()
  })

  test("should open settings panel when clicking gear", async ({ page }) => {
    await openSettingsPanel(page)
    await expect(page.locator(".leaflet-settings-panel")).toBeVisible()
  })

  test("should close settings panel when clicking gear again", async ({
    page,
  }) => {
    // Open
    await openSettingsPanel(page)
    await expect(page.locator(".leaflet-settings-panel")).toBeVisible()

    // Close
    await page.locator(".map-settings-button").click()
    await page.waitForTimeout(500)
    await expect(page.locator(".leaflet-settings-panel")).toHaveCount(0)
  })

  test("should display all settings form fields", async ({ page }) => {
    await openSettingsPanel(page)

    const expectedFields = [
      "#route-opacity",
      "#fog_of_war_meters",
      "#fog_of_war_threshold",
      "#meters_between_routes",
      "#minutes_between_routes",
      "#time_threshold_minutes",
      "#merge_threshold_minutes",
      "#speed_colored_routes",
      "#speed_color_scale",
      "#live_map_enabled",
      "#raw",
      "#simplified",
      "#edit-gradient-btn",
    ]

    for (const selector of expectedFields) {
      await expect(page.locator(selector)).toBeAttached()
    }
  })

  test("should show correct default values from user settings", async ({
    page,
  }) => {
    await openSettingsPanel(page)

    // Verify form values match the controller's userSettings
    const settings = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(
        (c) => c.identifier === "maps",
      )
      if (!controller?.userSettings) return null
      return {
        routeOpacity: controller.userSettings.route_opacity,
        fogOfWarMeters: controller.userSettings.fog_of_war_meters,
        metersBetweenRoutes: controller.userSettings.meters_between_routes,
        minutesBetweenRoutes: controller.userSettings.minutes_between_routes,
      }
    })

    if (settings) {
      const opacityValue = await page.locator("#route-opacity").inputValue()
      expect(opacityValue).toBe(String(settings.routeOpacity))

      const fogValue = await page.locator("#fog_of_war_meters").inputValue()
      expect(fogValue).toBe(String(settings.fogOfWarMeters))
    }
  })

  test("should have route opacity with valid range", async ({ page }) => {
    await openSettingsPanel(page)

    const opacityInput = page.locator("#route-opacity")
    await expect(opacityInput).toBeAttached()

    const min = await opacityInput.getAttribute("min")
    const max = await opacityInput.getAttribute("max")
    expect(min).toBe("10")
    expect(max).toBe("100")
  })

  test("should have points rendering mode radio buttons", async ({ page }) => {
    await openSettingsPanel(page)

    const rawRadio = page.locator("#raw")
    const simplifiedRadio = page.locator("#simplified")

    await expect(rawRadio).toBeAttached()
    await expect(simplifiedRadio).toBeAttached()

    // One should be checked
    const rawChecked = await rawRadio.isChecked()
    const simplifiedChecked = await simplifiedRadio.isChecked()
    expect(rawChecked || simplifiedChecked).toBe(true)
  })

  test("should have Update button", async ({ page }) => {
    await openSettingsPanel(page)

    const submitButton = page.locator(
      '#settings-form button[type="submit"], #settings-form input[type="submit"]',
    )
    await expect(submitButton).toBeVisible()

    const buttonText =
      (await submitButton.textContent().catch(() => null)) ||
      (await submitButton.getAttribute("value"))
    expect(buttonText).toMatch(/Update/i)
  })
})
