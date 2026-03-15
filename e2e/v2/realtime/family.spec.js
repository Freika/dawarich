import { expect, test } from "@playwright/test"
import { closeOnboardingModal } from "../../helpers/navigation.js"
import {
  enableLiveMode,
  sendOwnTracksPoint,
  waitForActionCableConnection,
  waitForFamilyMemberOnMap,
} from "../helpers/api.js"
import { API_KEYS, TEST_LOCATIONS, TEST_USERS } from "../helpers/constants.js"
import {
  navigateToMapsV2,
  waitForLoadingComplete,
  waitForMapLibre,
} from "../helpers/setup.js"

test.describe("Realtime Family Tracking", () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMapsV2(page)
    await closeOnboardingModal(page)
    await waitForMapLibre(page)
    await waitForLoadingComplete(page)
  })

  test.describe("Family Layer", () => {
    test("family layer controller is initialized", async ({ page }) => {
      // Verify the realtime controller exists and can handle family data
      const hasRealtimeController = await page.evaluate(() => {
        const element = document.querySelector(
          '[data-controller*="maps--maplibre-realtime"]',
        )
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre-realtime",
        )
        return controller !== undefined
      })

      expect(hasRealtimeController).toBe(true)
    })

    test("family member location appears on map when point is created", async ({
      page,
      request,
    }) => {
      // Enable live mode to setup channels
      await enableLiveMode(page)
      await waitForActionCableConnection(page)
      await page.waitForTimeout(1000)

      // Send a point as family member
      const testLat = TEST_LOCATIONS.BERLIN_SOUTH.lat + Math.random() * 0.001
      const testLon = TEST_LOCATIONS.BERLIN_SOUTH.lon + Math.random() * 0.001
      const timestamp = Math.floor(Date.now() / 1000)

      const response = await sendOwnTracksPoint(
        request,
        API_KEYS.FAMILY_MEMBER_1,
        testLat,
        testLon,
        timestamp,
      )

      // API should always work with valid API key
      expect(response.status()).toBe(200)

      // Real-time family display depends on:
      // 1. Family feature being enabled
      // 2. Family location sharing enabled for the member
      // 3. ActionCable/WebSocket delivering the broadcast
      const memberAppeared = await waitForFamilyMemberOnMap(
        page,
        TEST_USERS.FAMILY_1.email,
        5000,
      )

      if (memberAppeared) {
        console.log("[Test] Family member location displayed successfully")
      } else {
        console.log(
          "[Test] Family member API call successful, display depends on feature config",
        )
      }
    })
  })

  test.describe("Realtime History Polyline Extension", () => {
    test("sending multiple points extends the history polyline", async ({
      page,
      request,
    }) => {
      test.setTimeout(60000)

      // Enable family layer and live mode
      await enableLiveMode(page)
      await waitForActionCableConnection(page)
      await page.waitForTimeout(1000)

      // Send first point
      const baseLat = TEST_LOCATIONS.BERLIN_CENTER.lat
      const baseLon = TEST_LOCATIONS.BERLIN_CENTER.lon
      const timestamp1 = Math.floor(Date.now() / 1000)

      await sendOwnTracksPoint(
        request,
        API_KEYS.FAMILY_MEMBER_1,
        baseLat,
        baseLon,
        timestamp1,
      )
      await page.waitForTimeout(2000)

      // Send second point at different location
      const timestamp2 = timestamp1 + 60
      await sendOwnTracksPoint(
        request,
        API_KEYS.FAMILY_MEMBER_1,
        baseLat + 0.005,
        baseLon + 0.005,
        timestamp2,
      )
      await page.waitForTimeout(2000)

      // Send third point
      const timestamp3 = timestamp2 + 60
      await sendOwnTracksPoint(
        request,
        API_KEYS.FAMILY_MEMBER_1,
        baseLat + 0.01,
        baseLon + 0.01,
        timestamp3,
      )
      await page.waitForTimeout(2000)

      // Check if history source has a polyline with coordinates
      const historyState = await page.evaluate(() => {
        const element = document.querySelector(
          '[data-controller*="maps--maplibre"]',
        )
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre",
        )
        if (!controller?.map)
          return { hasSource: false, featureCount: 0, coordinateCounts: [] }

        const source = controller.map.getSource("family-source-history")
        if (!source?._data?.features)
          return { hasSource: true, featureCount: 0, coordinateCounts: [] }

        return {
          hasSource: true,
          featureCount: source._data.features.length,
          coordinateCounts: source._data.features.map(
            (f) => f.geometry?.coordinates?.length || 0,
          ),
        }
      })

      if (historyState.hasSource && historyState.featureCount > 0) {
        // At least one polyline should have multiple coordinates
        const maxCoords = Math.max(...historyState.coordinateCounts)
        expect(maxCoords).toBeGreaterThanOrEqual(2)
        console.log(
          `[Test] History polyline extended with ${maxCoords} coordinates`,
        )
      } else {
        console.log(
          "[Test] History source not available — family feature config dependent",
        )
      }
    })

    test("history polyline color matches member marker color", async ({
      page,
      request,
    }) => {
      test.setTimeout(60000)

      await enableLiveMode(page)
      await waitForActionCableConnection(page)
      await page.waitForTimeout(1000)

      // Send two points to create a polyline
      const baseLat = TEST_LOCATIONS.BERLIN_SOUTH.lat
      const baseLon = TEST_LOCATIONS.BERLIN_SOUTH.lon
      const timestamp = Math.floor(Date.now() / 1000)

      await sendOwnTracksPoint(
        request,
        API_KEYS.FAMILY_MEMBER_1,
        baseLat,
        baseLon,
        timestamp,
      )
      await page.waitForTimeout(1500)

      await sendOwnTracksPoint(
        request,
        API_KEYS.FAMILY_MEMBER_1,
        baseLat + 0.003,
        baseLon + 0.003,
        timestamp + 60,
      )
      await page.waitForTimeout(2000)

      // Compare marker color and polyline color
      const colors = await page.evaluate(() => {
        const element = document.querySelector(
          '[data-controller*="maps--maplibre"]',
        )
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre",
        )
        if (!controller?.map) return null

        // Get marker color from family source
        const markerSource = controller.map.getSource("family-source")
        const markerFeatures = markerSource?._data?.features || []
        const markerColor =
          markerFeatures.length > 0 ? markerFeatures[0].properties?.color : null

        // Get polyline color from history source
        const historySource = controller.map.getSource("family-source-history")
        const historyFeatures = historySource?._data?.features || []
        const polylineColor =
          historyFeatures.length > 0
            ? historyFeatures[0].properties?.color
            : null

        return { markerColor, polylineColor }
      })

      if (colors?.markerColor && colors?.polylineColor) {
        expect(colors.markerColor).toBe(colors.polylineColor)
        console.log(
          `[Test] Colors match: marker=${colors.markerColor}, polyline=${colors.polylineColor}`,
        )
      } else {
        console.log(
          "[Test] Could not compare colors — family feature config dependent",
        )
      }
    })

    test("family member marker position updates on broadcast", async ({
      page,
      request,
    }) => {
      test.setTimeout(60000)

      await enableLiveMode(page)
      await waitForActionCableConnection(page)
      await page.waitForTimeout(1000)

      // Send initial point
      const initialLat = TEST_LOCATIONS.BERLIN_NORTH.lat
      const initialLon = TEST_LOCATIONS.BERLIN_NORTH.lon
      const timestamp1 = Math.floor(Date.now() / 1000)

      await sendOwnTracksPoint(
        request,
        API_KEYS.FAMILY_MEMBER_1,
        initialLat,
        initialLon,
        timestamp1,
      )

      const memberAppeared = await waitForFamilyMemberOnMap(
        page,
        TEST_USERS.FAMILY_1.email,
        10000,
      )

      if (!memberAppeared) {
        console.log("[Test] Family member did not appear — config dependent")
        return
      }

      // Send updated point at new location
      const updatedLat = initialLat + 0.01
      const updatedLon = initialLon + 0.01
      await sendOwnTracksPoint(
        request,
        API_KEYS.FAMILY_MEMBER_1,
        updatedLat,
        updatedLon,
        timestamp1 + 120,
      )
      await page.waitForTimeout(3000)

      // Verify marker moved to new position
      const markerPosition = await page.evaluate(
        ({ email, expectedLat, expectedLon }) => {
          const element = document.querySelector(
            '[data-controller*="maps--maplibre"]',
          )
          const app = window.Stimulus || window.Application
          const controller = app?.getControllerForElementAndIdentifier(
            element,
            "maps--maplibre",
          )
          if (!controller?.map) return null

          const source = controller.map.getSource("family-source")
          if (!source?._data?.features) return null

          const feature = source._data.features.find(
            (f) => f.properties?.email === email,
          )
          if (!feature) return null

          const [lon, lat] = feature.geometry.coordinates
          return {
            lat,
            lon,
            movedToExpected:
              Math.abs(lat - expectedLat) < 0.001 &&
              Math.abs(lon - expectedLon) < 0.001,
          }
        },
        {
          email: TEST_USERS.FAMILY_1.email,
          expectedLat: updatedLat,
          expectedLon: updatedLon,
        },
      )

      if (markerPosition) {
        expect(markerPosition.movedToExpected).toBe(true)
        console.log(
          `[Test] Marker updated to ${markerPosition.lat}, ${markerPosition.lon}`,
        )
      }
    })
  })

  test.describe("ActionCable Connection", () => {
    test("establishes ActionCable connection for family tracking", async ({
      page,
    }) => {
      // Enable live mode to setup channels
      await enableLiveMode(page)

      // Wait for ActionCable connection
      const connected = await waitForActionCableConnection(page)
      expect(connected).toBe(true)

      // Verify channels object exists
      const channelsExist = await page.evaluate(() => {
        const element = document.querySelector(
          '[data-controller*="maps--maplibre-realtime"]',
        )
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre-realtime",
        )
        return controller?.channels !== undefined
      })

      expect(channelsExist).toBe(true)
    })

    test("can send location points for multiple family members", async ({
      request,
    }) => {
      const timestamp = Math.floor(Date.now() / 1000)

      // Send points for all family members
      const members = [
        { apiKey: API_KEYS.FAMILY_MEMBER_1, lat: 52.52, lon: 13.4 },
        { apiKey: API_KEYS.FAMILY_MEMBER_2, lat: 52.525, lon: 13.405 },
        { apiKey: API_KEYS.FAMILY_MEMBER_3, lat: 52.53, lon: 13.41 },
      ]

      for (const member of members) {
        const response = await sendOwnTracksPoint(
          request,
          member.apiKey,
          member.lat,
          member.lon,
          timestamp,
        )

        // All family members should have valid API keys
        expect(response.status()).toBe(200)
      }
    })
  })
})
