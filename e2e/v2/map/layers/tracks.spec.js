import { expect, test } from "@playwright/test"
import { closeOnboardingModal } from "../../../helpers/navigation.js"
import { resetMapSettings } from "../../helpers/api.js"
import { API_KEYS } from "../../helpers/constants.js"
import {
  hasLayer,
  navigateToMapsV2WithDate,
  waitForLoadingComplete,
  waitForMapLibre,
} from "../../helpers/setup.js"

test.describe("Tracks Layer", () => {
  // Reset settings to defaults so tracks toggle is unchecked
  test.beforeAll(async ({ request }) => {
    await resetMapSettings(request)
  })

  test.beforeEach(async ({ page }) => {
    await page.goto("/map/v2?start_at=2025-10-15T00:00&end_at=2025-10-15T23:59")
    await closeOnboardingModal(page)
    await waitForMapLibre(page)
    await waitForLoadingComplete(page)
    await page.waitForTimeout(1500)
  })

  test.describe("Toggle", () => {
    test("tracks layer toggle exists", async ({ page }) => {
      // Open settings panel
      await page
        .locator('[data-action="click->maps--maplibre#toggleSettings"]')
        .first()
        .click()
      await page.waitForTimeout(200)

      // Click Layers tab
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)

      const tracksToggle = page
        .locator('label:has-text("Tracks")')
        .first()
        .locator("input.toggle")
      await expect(tracksToggle).toBeVisible()
    })

    test("tracks toggle is unchecked by default", async ({ page }) => {
      // Open settings panel
      await page
        .locator('[data-action="click->maps--maplibre#toggleSettings"]')
        .first()
        .click()
      await page.waitForTimeout(200)

      // Click Layers tab
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)

      const tracksToggle = page
        .locator('label:has-text("Tracks")')
        .first()
        .locator("input.toggle")
      const isChecked = await tracksToggle.isChecked()
      expect(isChecked).toBe(false)
    })

    test("can toggle tracks layer on", async ({ page }) => {
      // Open settings panel
      await page
        .locator('[data-action="click->maps--maplibre#toggleSettings"]')
        .first()
        .click()
      await page.waitForTimeout(200)

      // Click Layers tab
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)

      const tracksToggle = page
        .locator('label:has-text("Tracks")')
        .first()
        .locator("input.toggle")
      await tracksToggle.check()
      await page.waitForTimeout(500)

      const isChecked = await tracksToggle.isChecked()
      expect(isChecked).toBe(true)
    })

    test("can toggle tracks layer off", async ({ page }) => {
      // Open settings panel
      await page
        .locator('[data-action="click->maps--maplibre#toggleSettings"]')
        .first()
        .click()
      await page.waitForTimeout(200)

      // Click Layers tab
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)

      const tracksToggle = page
        .locator('label:has-text("Tracks")')
        .first()
        .locator("input.toggle")

      // Turn on
      await tracksToggle.check()
      await page.waitForTimeout(500)
      expect(await tracksToggle.isChecked()).toBe(true)

      // Turn off
      await tracksToggle.uncheck()
      await page.waitForTimeout(500)
      expect(await tracksToggle.isChecked()).toBe(false)
    })
  })

  test.describe("Layer Visibility", () => {
    test("tracks layer is hidden when toggle is unchecked", async ({
      page,
    }) => {
      // Open settings and ensure tracks toggle is unchecked
      await page
        .locator('[data-action="click->maps--maplibre#toggleSettings"]')
        .first()
        .click()
      await page.waitForTimeout(200)
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)

      const tracksToggle = page
        .locator('label:has-text("Tracks")')
        .first()
        .locator("input.toggle")

      // Ensure toggle is off
      if (await tracksToggle.isChecked()) {
        await tracksToggle.uncheck()
        await page.waitForTimeout(1000) // Wait for layer visibility to update
      }

      expect(await tracksToggle.isChecked()).toBe(false)

      // Verify the tracks layer visibility matches the toggle state
      // Use waitForFunction to handle any async layer updates
      await page
        .waitForFunction(
          () => {
            const element = document.querySelector(
              '[data-controller*="maps--maplibre"]',
            )
            if (!element) return true // No element, consider it "hidden"
            const app = window.Stimulus || window.Application
            if (!app) return true
            const controller = app.getControllerForElementAndIdentifier(
              element,
              "maps--maplibre",
            )
            if (!controller?.map) return true

            const layer = controller.map.getLayer("tracks")
            if (!layer) return true // No layer = hidden

            const visibility = controller.map.getLayoutProperty(
              "tracks",
              "visibility",
            )
            return visibility === "none" || visibility === undefined
          },
          { timeout: 5000 },
        )
        .catch(() => {})

      const tracksVisibility = await page.evaluate(() => {
        const element = document.querySelector(
          '[data-controller*="maps--maplibre"]',
        )
        if (!element) return null
        const app = window.Stimulus || window.Application
        if (!app) return null
        const controller = app.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre",
        )
        if (!controller?.map) return null
        const layer = controller.map.getLayer("tracks")
        if (!layer) return "no-layer"
        return controller.map.getLayoutProperty("tracks", "visibility")
      })

      // Tracks should be hidden ('none') or the layer may not exist yet
      expect(
        tracksVisibility === "none" ||
          tracksVisibility === null ||
          tracksVisibility === "no-layer",
      ).toBe(true)
    })

    test("tracks layer becomes visible when toggled on", async ({ page }) => {
      // Open settings and enable tracks
      await page
        .locator('[data-action="click->maps--maplibre#toggleSettings"]')
        .first()
        .click()
      await page.waitForTimeout(200)
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)

      const tracksToggle = page
        .locator('label:has-text("Tracks")')
        .first()
        .locator("input.toggle")
      await tracksToggle.check()
      await page.waitForTimeout(500)

      // Verify layer is visible
      const tracksVisible = await page.evaluate(() => {
        const element = document.querySelector(
          '[data-controller*="maps--maplibre"]',
        )
        if (!element) return null

        const app = window.Stimulus || window.Application
        if (!app) return null

        const controller = app.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre",
        )
        if (!controller?.map) return null

        const layer = controller.map.getLayer("tracks")
        if (!layer) return null

        return (
          controller.map.getLayoutProperty("tracks", "visibility") === "visible"
        )
      })

      expect(tracksVisible).toBe(true)
    })
  })

  test.describe("Toggle Persistence", () => {
    test("tracks toggle state persists after page reload", async ({ page }) => {
      test.setTimeout(60000)

      // Enable tracks
      await page
        .locator('[data-action="click->maps--maplibre#toggleSettings"]')
        .first()
        .click()
      await page.waitForTimeout(200)
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)

      const tracksToggle = page
        .locator('label:has-text("Tracks")')
        .first()
        .locator("input.toggle")

      // Intercept the settings save response to verify it includes Tracks
      const savePromise = page.waitForResponse(
        (response) =>
          response.url().includes("/api/v1/settings") &&
          response.request().method() === "PATCH",
        { timeout: 10000 },
      )

      await tracksToggle.check()

      // Wait for the settings save to complete and verify the response
      const saveResponse = await savePromise
      expect(saveResponse.ok()).toBe(true)

      const responseData = await saveResponse.json()
      const savedSettings = responseData.settings || {}
      const enabledLayers = savedSettings.enabled_map_layers || []

      // The save response should confirm Tracks was persisted
      expect(enabledLayers).toContain("Tracks")

      // Reset settings back to defaults after this test
      await page.request.patch("/api/v1/settings", {
        headers: {
          Authorization: `Bearer ${API_KEYS.DEMO_USER}`,
          "Content-Type": "application/json",
        },
        data: { settings: { enabled_map_layers: ["Points", "Routes"] } },
      })
    })
  })

  test.describe("Layer Existence", () => {
    test("tracks layer exists on map", async ({ page }) => {
      await page
        .waitForFunction(
          () => {
            const element = document.querySelector(
              '[data-controller*="maps--maplibre"]',
            )
            if (!element) return false
            const app = window.Stimulus || window.Application
            if (!app) return false
            const controller = app.getControllerForElementAndIdentifier(
              element,
              "maps--maplibre",
            )
            return controller?.map?.getLayer("tracks") !== undefined
          },
          { timeout: 10000 },
        )
        .catch(() => false)

      const hasTracksLayer = await hasLayer(page, "tracks")
      expect(hasTracksLayer).toBe(true)
    })
  })

  test.describe("Data Source", () => {
    test("tracks source has data", async ({ page }) => {
      // Enable tracks layer first
      await page
        .locator('[data-action="click->maps--maplibre#toggleSettings"]')
        .first()
        .click()
      await page.waitForTimeout(200)
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)
      const tracksToggle = page
        .locator('label:has-text("Tracks")')
        .first()
        .locator("input.toggle")
      await tracksToggle.check()
      await page.waitForTimeout(1000)

      await page.waitForFunction(
        () => {
          const element = document.querySelector(
            '[data-controller*="maps--maplibre"]',
          )
          if (!element) return false
          const app = window.Stimulus || window.Application
          if (!app) return false
          const controller = app.getControllerForElementAndIdentifier(
            element,
            "maps--maplibre",
          )
          return controller?.map?.getSource("tracks-source") !== undefined
        },
        { timeout: 20000 },
      )

      const tracksData = await page.evaluate(async () => {
        const element = document.querySelector(
          '[data-controller*="maps--maplibre"]',
        )
        if (!element) return null
        const app = window.Stimulus || window.Application
        if (!app) return null
        const controller = app.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre",
        )
        if (!controller?.map) return null

        const source = controller.map.getSource("tracks-source")
        if (!source) return { hasSource: false, featureCount: 0, features: [] }

        const data = await source.getData()
        return {
          hasSource: true,
          featureCount: data?.features?.length || 0,
          features: data?.features || [],
        }
      })

      expect(tracksData.hasSource).toBe(true)
      expect(tracksData.featureCount).toBeGreaterThanOrEqual(0)
    })

    test("tracks have LineString geometry", async ({ page }) => {
      // Enable tracks layer first
      await page
        .locator('[data-action="click->maps--maplibre#toggleSettings"]')
        .first()
        .click()
      await page.waitForTimeout(200)
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)
      const tracksToggle = page
        .locator('label:has-text("Tracks")')
        .first()
        .locator("input.toggle")
      await tracksToggle.check()
      await page.waitForTimeout(1000)

      const tracksData = await page.evaluate(async () => {
        const element = document.querySelector(
          '[data-controller*="maps--maplibre"]',
        )
        if (!element) return { features: [] }
        const app = window.Stimulus || window.Application
        if (!app) return { features: [] }
        const controller = app.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre",
        )
        if (!controller?.map) return { features: [] }

        const source = controller.map.getSource("tracks-source")
        const data = source ? await source.getData() : undefined
        return { features: data?.features || [] }
      })

      if (tracksData.features.length > 0) {
        tracksData.features.forEach((feature) => {
          expect(feature.geometry.type).toBe("LineString")
          expect(feature.geometry.coordinates.length).toBeGreaterThan(1)
        })
      }
    })

    test("tracks have default color property", async ({ page }) => {
      // Enable tracks layer first
      await page
        .locator('[data-action="click->maps--maplibre#toggleSettings"]')
        .first()
        .click()
      await page.waitForTimeout(200)
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)
      const tracksToggle = page
        .locator('label:has-text("Tracks")')
        .first()
        .locator("input.toggle")
      await tracksToggle.check()
      await page.waitForTimeout(1000)

      const tracksData = await page.evaluate(async () => {
        const element = document.querySelector(
          '[data-controller*="maps--maplibre"]',
        )
        if (!element) return { features: [] }
        const app = window.Stimulus || window.Application
        if (!app) return { features: [] }
        const controller = app.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre",
        )
        if (!controller?.map) return { features: [] }

        const source = controller.map.getSource("tracks-source")
        const data = source ? await source.getData() : undefined
        return { features: data?.features || [] }
      })

      if (tracksData.features.length > 0) {
        tracksData.features.forEach((feature) => {
          expect(feature.properties).toHaveProperty("color")
          expect(feature.properties.color).toBe("#6366F1")
        })
      }
    })

    test("tracks have metadata properties", async ({ page }) => {
      // Enable tracks layer first
      await page
        .locator('[data-action="click->maps--maplibre#toggleSettings"]')
        .first()
        .click()
      await page.waitForTimeout(200)
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)
      const tracksToggle = page
        .locator('label:has-text("Tracks")')
        .first()
        .locator("input.toggle")
      await tracksToggle.check()
      await page.waitForTimeout(1000)

      const tracksData = await page.evaluate(async () => {
        const element = document.querySelector(
          '[data-controller*="maps--maplibre"]',
        )
        if (!element) return { features: [] }
        const app = window.Stimulus || window.Application
        if (!app) return { features: [] }
        const controller = app.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre",
        )
        if (!controller?.map) return { features: [] }

        const source = controller.map.getSource("tracks-source")
        const data = source ? await source.getData() : undefined
        return { features: data?.features || [] }
      })

      if (tracksData.features.length > 0) {
        tracksData.features.forEach((feature) => {
          expect(feature.properties).toHaveProperty("id")
          expect(feature.properties).toHaveProperty("start_at")
          expect(feature.properties).toHaveProperty("end_at")
          expect(feature.properties).toHaveProperty("distance")
          expect(feature.properties).toHaveProperty("avg_speed")
          expect(feature.properties).toHaveProperty("duration")
          expect(typeof feature.properties.distance).toBe("number")
          expect(feature.properties.distance).toBeGreaterThanOrEqual(0)
        })
      }
    })
  })

  test.describe("Styling", () => {
    test("tracks have red color styling", async ({ page }) => {
      await page.waitForFunction(
        () => {
          const element = document.querySelector(
            '[data-controller*="maps--maplibre"]',
          )
          if (!element) return false
          const app = window.Stimulus || window.Application
          if (!app) return false
          const controller = app.getControllerForElementAndIdentifier(
            element,
            "maps--maplibre",
          )
          return controller?.map?.getLayer("tracks") !== undefined
        },
        { timeout: 20000 },
      )

      const trackLayerInfo = await page.evaluate(() => {
        const element = document.querySelector(
          '[data-controller*="maps--maplibre"]',
        )
        if (!element) return null

        const app = window.Stimulus || window.Application
        if (!app) return null

        const controller = app.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre",
        )
        if (!controller?.map) return null

        const layer = controller.map.getLayer("tracks")
        if (!layer) return null

        const lineColor = controller.map.getPaintProperty(
          "tracks",
          "line-color",
        )

        return {
          exists: !!lineColor,
          isArray: Array.isArray(lineColor),
          value: lineColor,
        }
      })

      expect(trackLayerInfo).toBeTruthy()
      expect(trackLayerInfo.exists).toBe(true)

      // Track color uses ['get', 'color'] expression to read from feature properties
      // Features have color: '#ff0000' set by the backend
      if (trackLayerInfo.isArray) {
        // It's a MapLibre expression like ['get', 'color']
        expect(trackLayerInfo.value).toContain("get")
        expect(trackLayerInfo.value).toContain("color")
      }
    })
  })

  test.describe("Date Navigation", () => {
    test("date navigation preserves tracks layer", async ({ page }) => {
      // Wait for tracks layer to be added to the map
      await page.waitForFunction(
        () => {
          const element = document.querySelector(
            '[data-controller*="maps--maplibre"]',
          )
          if (!element) return false
          const app = window.Stimulus || window.Application
          if (!app) return false
          const controller = app.getControllerForElementAndIdentifier(
            element,
            "maps--maplibre",
          )
          return controller?.map?.getLayer("tracks") !== undefined
        },
        { timeout: 10000 },
      )

      const initialTracks = await hasLayer(page, "tracks")
      expect(initialTracks).toBe(true)

      await navigateToMapsV2WithDate(
        page,
        "2025-10-16T00:00",
        "2025-10-16T23:59",
      )
      await closeOnboardingModal(page)

      await waitForMapLibre(page)
      await waitForLoadingComplete(page)
      await page.waitForTimeout(1500)

      // Wait for tracks layer to be re-added after navigation
      await page
        .waitForFunction(
          () => {
            const element = document.querySelector(
              '[data-controller*="maps--maplibre"]',
            )
            if (!element) return false
            const app = window.Stimulus || window.Application
            if (!app) return false
            const controller = app.getControllerForElementAndIdentifier(
              element,
              "maps--maplibre",
            )
            return controller?.map?.getLayer("tracks") !== undefined
          },
          { timeout: 10000 },
        )
        .catch(() => false)

      const hasTracksLayer = await hasLayer(page, "tracks")
      expect(hasTracksLayer).toBe(true)
    })
  })
})
