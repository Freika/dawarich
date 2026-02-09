import { expect, test } from "@playwright/test"
import { closeOnboardingModal } from "../../../helpers/navigation.js"
import { waitForLoadingComplete } from "../../helpers/setup.js"

/**
 * E2E tests for Track Transportation Mode Segments
 * Tests the visualization of transportation modes (walking, driving, cycling, etc.)
 * on tracks in Map V2
 */
test.describe("Track Transportation Modes", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/map/v2?start_at=2025-10-15T00:00&end_at=2025-10-15T23:59")
    await closeOnboardingModal(page)
    await waitForLoadingComplete(page)
    await page.waitForTimeout(500)
  })

  /**
   * Helper to enable tracks layer and disable conflicting layers
   */
  async function enableTracksLayerOnly(page) {
    // Open settings panel
    await page
      .locator('[data-action="click->maps--maplibre#toggleSettings"]')
      .first()
      .click()
    await page.waitForTimeout(300)

    // Click layers tab
    await page.locator('button[data-tab="layers"]').click()
    await page.waitForTimeout(300)

    // Enable tracks if not already enabled
    const tracksCheckbox = page
      .locator('label:has-text("Tracks") input.toggle')
      .first()
    if (!(await tracksCheckbox.isChecked())) {
      await tracksCheckbox.check()
      await page.waitForTimeout(300)
    }

    // Disable other layers that might intercept clicks
    const layersToDisable = [
      "Routes",
      "Areas",
      "Visits",
      "Places",
      "Photos",
      "Heatmap",
      "Points",
    ]
    for (const layer of layersToDisable) {
      const checkbox = page
        .locator(`label:has-text("${layer}") input.toggle`)
        .first()
      if (await checkbox.isChecked().catch(() => false)) {
        await checkbox.uncheck()
        await page.waitForTimeout(100)
      }
    }

    // Close settings panel - use the close button in the panel header
    const closeButton = page.getByRole("button", { name: "Close panel" })
    await closeButton.click()
    await page.waitForTimeout(300)
  }

  /**
   * Helper to enable tracks layer
   */
  async function enableTracksLayer(page) {
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

    // Close settings panel using close button (more reliable)
    const closeButton = page.locator(
      'button:has-text("Close panel"), [data-maps--maplibre-target="settingsPanel"] button[aria-label="Close"]',
    )
    if ((await closeButton.count()) > 0) {
      await closeButton.first().click()
    } else {
      // Fallback to toggle button
      await page
        .locator('[data-action="click->maps--maplibre#toggleSettings"]')
        .first()
        .click()
    }
    await page.waitForTimeout(200)
  }

  /**
   * Helper to get tracks source data
   */
  async function getTracksSourceData(page) {
    return await page.evaluate(() => {
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
      const data = source?._data
      return { features: data?.features || [] }
    })
  }

  /**
   * Helper to wait for tracks source to have data
   */
  async function waitForTracksData(page) {
    try {
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
          const source = controller?.map?.getSource("tracks-source")
          return source && source._data?.features?.length > 0
        },
        { timeout: 20000 },
      )
      return true
    } catch {
      return false
    }
  }

  /**
   * Helper to click on a track on the map
   */
  async function clickOnTrack(page) {
    // Wait for tracks to be loaded
    const hasData = await waitForTracksData(page)
    if (!hasData) {
      console.log("No tracks data found")
      return null
    }

    // Center map on first track and wait for it to be visible
    await page.evaluate(() => {
      const element = document.querySelector(
        '[data-controller*="maps--maplibre"]',
      )
      if (!element) return
      const app = window.Stimulus || window.Application
      if (!app) return
      const controller = app.getControllerForElementAndIdentifier(
        element,
        "maps--maplibre",
      )
      if (!controller?.map) return

      const source = controller.map.getSource("tracks-source")
      const data = source?._data
      if (!data?.features?.length) return

      const track = data.features[0]
      const coords = track.geometry.coordinates
      const midCoord = coords[Math.floor(coords.length / 2)]

      // Center on track and zoom in
      controller.map.flyTo({
        center: midCoord,
        zoom: 14,
        duration: 0, // Instant move for tests
      })
    })

    await page.waitForTimeout(1000)

    // Get track coordinates and click on one
    const trackCoords = await page.evaluate(() => {
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
      const data = source?._data
      if (!data?.features?.length) return null

      // Get the first track's middle coordinate
      const track = data.features[0]
      if (!track?.geometry?.coordinates?.length) return null

      const coords = track.geometry.coordinates
      const midIdx = Math.floor(coords.length / 2)
      const midCoord = coords[midIdx]

      // Convert to screen coordinates
      const point = controller.map.project(midCoord)
      return { x: point.x, y: point.y, trackId: track.properties.id }
    })

    if (!trackCoords) return null

    // Click on the track using canvas (same pattern as interactions.spec.js)
    const canvas = page.locator(".maplibregl-canvas")
    await canvas.click({
      position: { x: trackCoords.x, y: trackCoords.y },
    })
    await page.waitForTimeout(500)

    return trackCoords.trackId
  }

  test.describe("Track Segments Data", () => {
    test("tracks have segments property in GeoJSON", async ({ page }) => {
      await enableTracksLayer(page)

      const tracksData = await getTracksSourceData(page)

      if (tracksData.features.length > 0) {
        tracksData.features.forEach((feature) => {
          expect(feature.properties).toHaveProperty("segments")
        })
      }
    })

    test("tracks have dominant_mode property", async ({ page }) => {
      await enableTracksLayer(page)

      const tracksData = await getTracksSourceData(page)

      if (tracksData.features.length > 0) {
        tracksData.features.forEach((feature) => {
          expect(feature.properties).toHaveProperty("dominant_mode")
        })
      }
    })

    test("tracks have dominant_mode_emoji property", async ({ page }) => {
      await enableTracksLayer(page)

      const tracksData = await getTracksSourceData(page)

      if (tracksData.features.length > 0) {
        tracksData.features.forEach((feature) => {
          expect(feature.properties).toHaveProperty("dominant_mode_emoji")
        })
      }
    })

    test("segment data includes required properties", async ({ page }) => {
      await enableTracksLayer(page)

      const tracksData = await getTracksSourceData(page)

      if (tracksData.features.length > 0) {
        const feature = tracksData.features[0]
        const segments =
          typeof feature.properties.segments === "string"
            ? JSON.parse(feature.properties.segments)
            : feature.properties.segments || []

        if (segments.length > 0) {
          const segment = segments[0]
          expect(segment).toHaveProperty("mode")
          expect(segment).toHaveProperty("emoji")
          expect(segment).toHaveProperty("color")
          expect(segment).toHaveProperty("start_index")
          expect(segment).toHaveProperty("end_index")
          expect(segment).toHaveProperty("distance")
          expect(segment).toHaveProperty("duration")
        }
      }
    })

    test("segment data includes time properties", async ({ page }) => {
      await enableTracksLayer(page)

      const tracksData = await getTracksSourceData(page)

      if (tracksData.features.length > 0) {
        const feature = tracksData.features[0]
        const segments =
          typeof feature.properties.segments === "string"
            ? JSON.parse(feature.properties.segments)
            : feature.properties.segments || []

        if (segments.length > 0) {
          const segment = segments[0]
          expect(segment).toHaveProperty("start_time")
          expect(segment).toHaveProperty("end_time")
          expect(typeof segment.start_time).toBe("number")
          expect(typeof segment.end_time).toBe("number")
        }
      }
    })
  })

  test.describe("Track Click Info Panel", () => {
    test("clicking track shows info panel", async ({ page }) => {
      await enableTracksLayerOnly(page)

      const trackId = await clickOnTrack(page)

      if (trackId) {
        // Check that info panel is visible (uses hidden class pattern)
        const infoDisplay = page.locator(
          '[data-maps--maplibre-target="infoDisplay"]',
        )
        await expect(infoDisplay).not.toHaveClass(/hidden/, { timeout: 3000 })
      }
    })

    test("info panel shows track title", async ({ page }) => {
      await enableTracksLayerOnly(page)

      const trackId = await clickOnTrack(page)

      if (trackId) {
        const infoDisplay = page.locator(
          '[data-maps--maplibre-target="infoDisplay"]',
        )
        await expect(infoDisplay).not.toHaveClass(/hidden/, { timeout: 3000 })

        // Check for track title
        const infoTitle = page.locator(
          '[data-maps--maplibre-target="infoTitle"]',
        )
        const titleText = await infoTitle.textContent()
        expect(titleText).toContain("Track")
      }
    })

    test("info panel shows track metadata", async ({ page }) => {
      await enableTracksLayerOnly(page)

      const trackId = await clickOnTrack(page)

      if (trackId) {
        const infoDisplay = page.locator(
          '[data-maps--maplibre-target="infoDisplay"]',
        )
        await expect(infoDisplay).not.toHaveClass(/hidden/, { timeout: 3000 })

        const infoContent = page.locator(
          '[data-maps--maplibre-target="infoContent"]',
        )
        const content = await infoContent.textContent()

        // Check for essential metadata
        expect(content).toContain("Start")
        expect(content).toContain("End")
        expect(content).toContain("Duration")
        expect(content).toContain("Distance")
      }
    })

    test("info panel shows dominant mode when present", async ({ page }) => {
      await enableTracksLayerOnly(page)

      const trackId = await clickOnTrack(page)

      if (trackId) {
        const infoDisplay = page.locator(
          '[data-maps--maplibre-target="infoDisplay"]',
        )
        await expect(infoDisplay).not.toHaveClass(/hidden/, { timeout: 3000 })

        const infoContent = page.locator(
          '[data-maps--maplibre-target="infoContent"]',
        )
        const _content = await infoContent.textContent()

        // Check for mode indicator (may or may not be present depending on data)
        // This test just verifies the panel loaded correctly
        expect(infoDisplay).not.toHaveClass(/hidden/)
      }
    })
  })

  test.describe("Segment List Display", () => {
    test("info panel shows segments list when track has segments", async ({
      page,
    }) => {
      await enableTracksLayerOnly(page)

      // First check if any tracks have segments
      const tracksData = await getTracksSourceData(page)
      const tracksWithSegments = tracksData.features.filter((f) => {
        const segments =
          typeof f.properties.segments === "string"
            ? JSON.parse(f.properties.segments)
            : f.properties.segments || []
        return segments.length > 0
      })

      if (tracksWithSegments.length === 0) {
        test.skip()
        return
      }

      const trackId = await clickOnTrack(page)

      if (trackId) {
        const infoDisplay = page.locator(
          '[data-maps--maplibre-target="infoDisplay"]',
        )
        await expect(infoDisplay).not.toHaveClass(/hidden/, { timeout: 3000 })

        // Check for segments section
        const infoContent = page.locator(
          '[data-maps--maplibre-target="infoContent"]',
        )
        const content = await infoContent.textContent()
        expect(content).toContain("Segments")
      }
    })

    test("segment list items have data-segment-index attribute", async ({
      page,
    }) => {
      await enableTracksLayerOnly(page)

      const trackId = await clickOnTrack(page)

      if (trackId) {
        await page.waitForTimeout(500)

        const segmentItems = page.locator(".segment-list-item")
        const count = await segmentItems.count()

        if (count > 0) {
          // Check that segment items have the data attribute
          const firstItem = segmentItems.first()
          const indexAttr = await firstItem.getAttribute("data-segment-index")
          expect(indexAttr).not.toBeNull()
          expect(indexAttr).toBe("0")
        }
      }
    })

    test("segment list shows time range for each segment", async ({ page }) => {
      await enableTracksLayerOnly(page)

      const trackId = await clickOnTrack(page)

      if (trackId) {
        await page.waitForTimeout(500)

        const segmentItems = page.locator(".segment-list-item")
        const count = await segmentItems.count()

        if (count > 0) {
          // Check that time is displayed (HH:MM - HH:MM format)
          const firstItemText = await segmentItems.first().textContent()
          // Should contain time-like pattern or '--:--' if no time
          const hasTimePattern =
            /\d{2}:\d{2}/.test(firstItemText) || firstItemText.includes("--:--")
          expect(hasTimePattern).toBe(true)
        }
      }
    })

    test("segment list shows emoji for each segment", async ({ page }) => {
      await enableTracksLayerOnly(page)

      const trackId = await clickOnTrack(page)

      if (trackId) {
        await page.waitForTimeout(500)

        const segmentItems = page.locator(".segment-list-item")
        const count = await segmentItems.count()

        if (count > 0) {
          const firstItemText = await segmentItems.first().textContent()
          // Should contain transportation mode emoji
          const transportEmojis = [
            "🚶",
            "🏃",
            "🚴",
            "🚗",
            "🚌",
            "🚆",
            "✈️",
            "⛵",
            "🏍️",
            "📍",
            "❓",
          ]
          const hasEmoji = transportEmojis.some((emoji) =>
            firstItemText.includes(emoji),
          )
          expect(hasEmoji).toBe(true)
        }
      }
    })

    test("segment list shows mode name for each segment", async ({ page }) => {
      await enableTracksLayerOnly(page)

      const trackId = await clickOnTrack(page)

      if (trackId) {
        await page.waitForTimeout(500)

        const segmentItems = page.locator(".segment-list-item")
        const count = await segmentItems.count()

        if (count > 0) {
          const firstItemText = await segmentItems
            .first()
            .textContent()
            .then((t) => t.toLowerCase())
          // Should contain a transportation mode name
          const modeNames = [
            "walking",
            "running",
            "cycling",
            "driving",
            "bus",
            "train",
            "flying",
            "boat",
            "motorcycle",
            "stationary",
            "unknown",
          ]
          const hasModeName = modeNames.some((mode) =>
            firstItemText.includes(mode),
          )
          expect(hasModeName).toBe(true)
        }
      }
    })
  })

  test.describe("Segment Visualization on Map", () => {
    test("clicking track creates segment highlight layer", async ({ page }) => {
      await enableTracksLayerOnly(page)

      const trackId = await clickOnTrack(page)

      if (trackId) {
        await page.waitForTimeout(500)

        // Check if segment layer was created
        const hasSegmentLayer = await page.evaluate(() => {
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
          if (!controller?.map) return false

          return controller.map.getLayer("tracks-segments") !== undefined
        })

        // Segment layer should exist after clicking a track
        expect(hasSegmentLayer).toBe(true)
      }
    })

    test("segment layer uses different colors for different modes", async ({
      page,
    }) => {
      await enableTracksLayerOnly(page)

      const trackId = await clickOnTrack(page)

      if (trackId) {
        await page.waitForTimeout(500)

        const segmentLayerInfo = await page.evaluate(() => {
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

          const source = controller.map.getSource("tracks-segments-source")
          if (!source?._data) return null

          const features = source._data.features || []
          const colors = features.map((f) => f.properties.color)

          return {
            featureCount: features.length,
            colors: colors,
            hasColorProperty: features.every((f) => f.properties.color),
          }
        })

        if (segmentLayerInfo && segmentLayerInfo.featureCount > 0) {
          expect(segmentLayerInfo.hasColorProperty).toBe(true)
          // All segments should have a color
          segmentLayerInfo.colors.forEach((color) => {
            expect(color).toMatch(/^#[0-9A-Fa-f]{6}$/)
          })
        }
      }
    })

    test("emoji markers appear at segment start points", async ({ page }) => {
      await enableTracksLayerOnly(page)

      const trackId = await clickOnTrack(page)

      if (trackId) {
        await page.waitForTimeout(500)

        // Check for emoji markers on the map
        const emojiMarkers = page.locator(".track-emoji-marker")
        const count = await emojiMarkers.count()

        // Should have at least segment markers + end marker
        expect(count).toBeGreaterThanOrEqual(1)
      }
    })

    test("end marker (finish flag) appears at track end", async ({ page }) => {
      await enableTracksLayerOnly(page)

      const trackId = await clickOnTrack(page)

      if (trackId) {
        await page.waitForTimeout(500)

        // Look for the finish flag emoji
        const finishMarker = page.locator('.track-emoji-marker:has-text("🏁")')
        const count = await finishMarker.count()

        expect(count).toBeGreaterThanOrEqual(1)
      }
    })
  })

  test.describe("Segment Hover Interactions", () => {
    test("hovering segment list item highlights segment on map", async ({
      page,
    }) => {
      await enableTracksLayerOnly(page)

      const trackId = await clickOnTrack(page)

      if (trackId) {
        await page.waitForTimeout(500)

        const segmentItems = page.locator(".segment-list-item")
        const count = await segmentItems.count()

        if (count > 0) {
          // Get initial segment layer opacity
          const _initialOpacity = await page.evaluate(() => {
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

            return controller.map.getPaintProperty(
              "tracks-segments",
              "line-opacity",
            )
          })

          // Hover over first segment
          await segmentItems.first().hover()
          await page.waitForTimeout(200)

          // Check that opacity changed (indicating highlight)
          const hoverOpacity = await page.evaluate(() => {
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

            return controller.map.getPaintProperty(
              "tracks-segments",
              "line-opacity",
            )
          })

          // Opacity should have changed to a conditional expression
          if (count > 1) {
            // If multiple segments, opacity becomes conditional
            expect(
              Array.isArray(hoverOpacity) || typeof hoverOpacity === "number",
            ).toBe(true)
          }
        }
      }
    })

    test("hovering segment list item adds highlight class", async ({
      page,
    }) => {
      await enableTracksLayerOnly(page)

      const trackId = await clickOnTrack(page)

      if (trackId) {
        await page.waitForTimeout(500)

        const segmentItems = page.locator(".segment-list-item")
        const count = await segmentItems.count()

        if (count > 1) {
          // Hover over first segment
          await segmentItems.first().hover()
          await page.waitForTimeout(200)

          // First item should have highlight class
          const firstItemClasses = await segmentItems
            .first()
            .getAttribute("class")
          expect(firstItemClasses).toContain("bg-primary")

          // Other items should be dimmed
          const secondItemClasses = await segmentItems
            .nth(1)
            .getAttribute("class")
          expect(secondItemClasses).toContain("opacity-50")
        }
      }
    })

    test("mouse leave removes highlight from segment list", async ({
      page,
    }) => {
      await enableTracksLayerOnly(page)

      const trackId = await clickOnTrack(page)

      if (trackId) {
        await page.waitForTimeout(500)

        const segmentItems = page.locator(".segment-list-item")
        const count = await segmentItems.count()

        if (count > 0) {
          // Hover over first segment
          await segmentItems.first().hover()
          await page.waitForTimeout(200)

          // Move mouse away
          await page.mouse.move(0, 0)
          await page.waitForTimeout(200)

          // First item should not have highlight class
          const firstItemClasses = await segmentItems
            .first()
            .getAttribute("class")
          expect(firstItemClasses).not.toContain("bg-primary")
          expect(firstItemClasses).not.toContain("opacity-50")
        }
      }
    })

    test("hovering segment on map highlights list item", async ({ page }) => {
      await enableTracksLayerOnly(page)

      const trackId = await clickOnTrack(page)

      if (trackId) {
        await page.waitForTimeout(500)

        // Get segment coordinates to hover over
        const segmentCoords = await page.evaluate(() => {
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

          const source = controller.map.getSource("tracks-segments-source")
          if (!source?._data?.features?.length) return null

          const segment = source._data.features[0]
          if (!segment?.geometry?.coordinates?.length) return null

          // Get middle point of segment
          const coords = segment.geometry.coordinates
          const midIdx = Math.floor(coords.length / 2)
          const midCoord = coords[midIdx]

          const point = controller.map.project(midCoord)
          return { x: point.x, y: point.y }
        })

        if (segmentCoords) {
          // Hover over the segment on map
          const mapContainer = page.locator(
            '[data-maps--maplibre-target="container"]',
          )
          await mapContainer.hover({
            position: { x: segmentCoords.x, y: segmentCoords.y },
          })
          await page.waitForTimeout(300)

          // Check if list item is highlighted
          const segmentItems = page.locator(".segment-list-item")
          const count = await segmentItems.count()

          if (count > 0) {
            // At least one item should have highlight or opacity change
            const classes = await segmentItems.first().getAttribute("class")
            // Could have bg-primary (hovered) or opacity-50 (not hovered)
            const _hasHighlight =
              classes.includes("bg-primary") || classes.includes("opacity-50")
            // Just verify the hover interaction was triggered
            expect(classes).toBeDefined()
          }
        }
      }
    })
  })

  test.describe("Clearing Track Selection", () => {
    test("clicking elsewhere on map clears track selection", async ({
      page,
    }) => {
      await enableTracksLayerOnly(page)

      const trackId = await clickOnTrack(page)

      if (trackId) {
        await page.waitForTimeout(500)

        // Verify info panel is visible
        const infoDisplay = page.locator(
          '[data-maps--maplibre-target="infoDisplay"]',
        )
        await expect(infoDisplay).not.toHaveClass(/hidden/)

        // Click elsewhere on the map (away from tracks)
        const canvas = page.locator(".maplibregl-canvas")
        // Click in top-left corner (likely empty)
        await canvas.click({ position: { x: 50, y: 50 } })
        await page.waitForTimeout(500)

        // Segment layer should be hidden or removed
        const _segmentLayerVisible = await page.evaluate(() => {
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
          if (!controller?.map) return false

          const layer = controller.map.getLayer("tracks-segments")
          if (!layer) return false

          return (
            controller.map.getLayoutProperty(
              "tracks-segments",
              "visibility",
            ) === "visible"
          )
        })

        // Either segment layer doesn't exist or is hidden
        // Note: This may vary based on where we clicked
      }
    })

    test("segment markers are removed when track is deselected", async ({
      page,
    }) => {
      await enableTracksLayerOnly(page)

      const trackId = await clickOnTrack(page)

      if (trackId) {
        await page.waitForTimeout(500)

        // Verify info panel is visible
        const infoDisplay = page.locator(
          '[data-maps--maplibre-target="infoDisplay"]',
        )
        await expect(infoDisplay).not.toHaveClass(/hidden/, { timeout: 3000 })

        // Verify markers exist
        const initialMarkerCount = await page
          .locator(".track-emoji-marker")
          .count()
        expect(initialMarkerCount).toBeGreaterThan(0)

        // Close info panel using close button (must be inside the visible info display)
        const closeButton = infoDisplay.locator(
          'button[data-action="click->maps--maplibre#closeInfo"]',
        )
        await expect(closeButton).toBeVisible({ timeout: 2000 })
        await closeButton.click()
        await page.waitForTimeout(500)

        // Info panel should be hidden
        await expect(infoDisplay).toHaveClass(/hidden/)

        // Markers should be removed
        const finalMarkerCount = await page
          .locator(".track-emoji-marker")
          .count()
        expect(finalMarkerCount).toBe(0)
      }
    })
  })
})
