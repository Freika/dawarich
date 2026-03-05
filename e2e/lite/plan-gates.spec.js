import { expect, test } from "@playwright/test"
import { API_KEYS } from "../v2/helpers/constants.js"
import { openSettingsTab, waitForMapLibre } from "../v2/helpers/setup.js"

/**
 * Wait for a toast containing the expected substring.
 * Toast uses textContent (HTML tags render as plain text).
 */
async function waitForToast(page, substring, timeout = 5000) {
  const toast = page.locator(".toast-container .toast")
  await expect(toast.filter({ hasText: substring }).first()).toBeVisible({
    timeout,
  })
  return toast.filter({ hasText: substring }).first()
}

/**
 * Wait for the upgrade banner containing the expected substring.
 */
async function waitForBanner(page, substring, timeout = 5000) {
  const banner = page.locator(".map-upgrade-banner")
  await expect(banner.filter({ hasText: substring }).first()).toBeVisible({
    timeout,
  })
  return banner.filter({ hasText: substring }).first()
}

// ---------------------------------------------------------------------------
// Map Layer Gating
// ---------------------------------------------------------------------------
test.describe("Map Layer Gating", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/map/v2", { waitUntil: "domcontentloaded" })
    await waitForMapLibre(page)
  })

  test("Heatmap toggle shows preview toast", async ({ page }) => {
    await openSettingsTab(page, "layers")

    const toggle = page.locator('[data-maps--maplibre-target="heatmapToggle"]')
    await toggle.check({ force: true })

    const toast = await waitForToast(page, "Previewing Heatmap")
    await expect(toast).toContainText("20 seconds")
  })

  test("Fog of War toggle shows preview toast", async ({ page }) => {
    await openSettingsTab(page, "layers")

    const toggle = page.locator('[data-maps--maplibre-target="fogToggle"]')
    await toggle.check({ force: true })

    await waitForToast(page, "Previewing Fog of War")
  })

  test("Scratch Map toggle shows preview toast", async ({ page }) => {
    await openSettingsTab(page, "layers")

    const toggle = page.locator('[data-maps--maplibre-target="scratchToggle"]')
    await toggle.check({ force: true })

    await waitForToast(page, "Previewing Scratch")
  })

  test("Globe toggle shows upgrade banner", async ({ page }) => {
    await openSettingsTab(page, "settings")

    const toggle = page.locator('[data-maps--maplibre-target="globeToggle"]')
    await toggle.check({ force: true })

    const banner = await waitForBanner(page, "Globe View is a Pro feature")
    await expect(banner.locator(".map-upgrade-banner-cta")).toBeVisible()

    // Toggle should be unchecked after the gate rejects it
    await expect(toggle).not.toBeChecked()
  })
})

// ---------------------------------------------------------------------------
// Data Retention
// ---------------------------------------------------------------------------
test.describe("Data Retention", () => {
  test("shows data window upsell banner on map load", async ({ page }) => {
    await page.goto("/map/v2", { waitUntil: "domcontentloaded" })
    await waitForMapLibre(page)

    const banner = await waitForBanner(
      page,
      "12 months of searchable history",
      10000,
    )
    await expect(banner.locator(".map-upgrade-banner-cta")).toBeVisible()
  })

  test("banner can be dismissed", async ({ page }) => {
    await page.goto("/map/v2", { waitUntil: "domcontentloaded" })
    await waitForMapLibre(page)

    const banner = await waitForBanner(
      page,
      "12 months of searchable history",
      10000,
    )
    await banner.locator(".map-upgrade-banner-dismiss").click()
    await expect(page.locator(".map-upgrade-banner")).not.toBeVisible()
  })

  test("API excludes points older than 12 months", async ({ page }) => {
    // Query a wide date range that would include old points
    const threeYearsAgo = new Date()
    threeYearsAgo.setFullYear(threeYearsAgo.getFullYear() - 3)
    const startAt = threeYearsAgo.toISOString()
    const endAt = new Date().toISOString()

    const response = await page.request.get(
      `/api/v1/points?start_at=${startAt}&end_at=${endAt}&per_page=100`,
      {
        headers: {
          Authorization: `Bearer ${API_KEYS.LITE_USER}`,
        },
      },
    )

    expect(response.status()).toBe(200)

    const points = await response.json()
    expect(points.length).toBeGreaterThan(0)

    // All returned points must be within the 12-month window
    const twelveMonthsAgo = Date.now() / 1000 - 12 * 30 * 24 * 60 * 60
    for (const point of points) {
      expect(point.timestamp).toBeGreaterThanOrEqual(
        Math.floor(twelveMonthsAgo),
      )
    }
  })
})

// ---------------------------------------------------------------------------
// Settings Gating
// ---------------------------------------------------------------------------
test.describe("Settings Gating", () => {
  test("integrations page shows upgrade prompt", async ({ page }) => {
    await page.goto("/settings/integrations", {
      waitUntil: "domcontentloaded",
    })

    await expect(page.locator("text=Upgrade to Pro")).toBeVisible()
    // Immich URL input should not be visible behind the gate
    await expect(
      page.locator('input[placeholder*="Immich"]').first(),
    ).not.toBeVisible()
  })
})

// ---------------------------------------------------------------------------
// API Write Gating
// ---------------------------------------------------------------------------
test.describe("API Write Gating", () => {
  test("POST points returns 403 for Lite user", async ({ page }) => {
    const response = await page.request.post("/api/v1/points", {
      headers: {
        Authorization: `Bearer ${API_KEYS.LITE_USER}`,
        "Content-Type": "application/json",
      },
      data: {
        locations: [
          {
            type: "Feature",
            geometry: { type: "Point", coordinates: [13.405, 52.52] },
            properties: {
              timestamp: Math.floor(Date.now() / 1000),
              altitude: 50,
              speed: 0,
            },
          },
        ],
      },
    })

    expect(response.status()).toBe(403)
    const body = await response.json()
    expect(body.error).toBe("write_api_restricted")
  })
})
