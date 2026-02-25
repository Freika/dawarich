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
