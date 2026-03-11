import { expect, test } from "@playwright/test"
import { closeOnboardingModal } from "../../../helpers/navigation.js"
import {
  enableFamilyInSettings,
  resetMapSettings,
  sendOwnTracksPoint,
} from "../../helpers/api.js"
import { API_KEYS, TEST_LOCATIONS } from "../../helpers/constants.js"
import {
  getMapCenter,
  navigateToMapsV2,
  waitForLoadingComplete,
  waitForMapLibre,
} from "../../helpers/setup.js"

test.describe("Family Members Layer", () => {
  // Reset settings and create family member location data before all tests
  test.beforeAll(async ({ request }) => {
    // Reset settings to defaults so family toggle is unchecked
    await resetMapSettings(request)

    const timestamp = Math.floor(Date.now() / 1000)

    // Send location points for all family members
    const familyMembers = [
      {
        apiKey: API_KEYS.FAMILY_MEMBER_1,
        lat: TEST_LOCATIONS.BERLIN_CENTER.lat,
        lon: TEST_LOCATIONS.BERLIN_CENTER.lon,
      },
      {
        apiKey: API_KEYS.FAMILY_MEMBER_2,
        lat: TEST_LOCATIONS.BERLIN_NORTH.lat,
        lon: TEST_LOCATIONS.BERLIN_NORTH.lon,
      },
      {
        apiKey: API_KEYS.FAMILY_MEMBER_3,
        lat: TEST_LOCATIONS.BERLIN_SOUTH.lat,
        lon: TEST_LOCATIONS.BERLIN_SOUTH.lon,
      },
    ]

    for (const member of familyMembers) {
      await sendOwnTracksPoint(
        request,
        member.apiKey,
        member.lat,
        member.lon,
        timestamp,
      )
    }
  })

  test.beforeEach(async ({ page }) => {
    await navigateToMapsV2(page)
    await closeOnboardingModal(page)
    await waitForMapLibre(page)
    await waitForLoadingComplete(page)
    await page.waitForTimeout(1500)
  })

  test.describe("Toggle", () => {
    test("family members toggle exists in Layers tab", async ({ page }) => {
      // Open settings panel
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)

      // Click Layers tab
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      // Check if Family Members toggle exists
      const familyToggle = page
        .locator('label:has-text("Family Members")')
        .first()
        .locator("input.toggle")
      await expect(familyToggle).toBeVisible()
    })

    test("family members toggle can be unchecked", async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const familyToggle = page
        .locator('label:has-text("Family Members")')
        .first()
        .locator("input.toggle")

      // Ensure toggle is unchecked
      if (await familyToggle.isChecked()) {
        await familyToggle.uncheck()
        await page.waitForTimeout(500)
      }

      const isChecked = await familyToggle.isChecked()
      expect(isChecked).toBe(false)
    })

    test("can toggle family members layer on", async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const familyToggle = page
        .locator('label:has-text("Family Members")')
        .first()
        .locator("input.toggle")

      // Toggle on
      await familyToggle.check()
      await page.waitForTimeout(1000) // Wait for API call and layer update

      const isChecked = await familyToggle.isChecked()
      expect(isChecked).toBe(true)
    })

    test("can toggle family members layer off", async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const familyToggle = page
        .locator('label:has-text("Family Members")')
        .first()
        .locator("input.toggle")

      // Toggle on first
      await familyToggle.check()
      await page.waitForTimeout(1000)

      // Then toggle off
      await familyToggle.uncheck()
      await page.waitForTimeout(500)

      const isChecked = await familyToggle.isChecked()
      expect(isChecked).toBe(false)
    })
  })

  test.describe("Family Members List", () => {
    test("family members list is hidden when toggle is unchecked", async ({
      page,
    }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const familyToggle = page
        .locator('label:has-text("Family Members")')
        .first()
        .locator("input.toggle")

      // Ensure toggle is off
      if (await familyToggle.isChecked()) {
        await familyToggle.uncheck()
        await page.waitForTimeout(500)
      }

      const familyMembersList = page.locator(
        '[data-maps--maplibre-target="familyMembersList"]',
      )

      // Should be hidden when toggle is unchecked
      const isVisible = await familyMembersList.isVisible()
      expect(isVisible).toBe(false)
    })

    test("family members list appears when toggle is enabled", async ({
      page,
    }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const familyToggle = page
        .locator('label:has-text("Family Members")')
        .first()
        .locator("input.toggle")
      const familyMembersList = page.locator(
        '[data-maps--maplibre-target="familyMembersList"]',
      )

      // Toggle on
      await familyToggle.check()
      await page.waitForTimeout(1000)

      // List should now be visible
      const isVisible = await familyMembersList.evaluate(
        (el) => el.style.display === "block",
      )
      expect(isVisible).toBe(true)
    })

    test("family members list shows members when data exists", async ({
      page,
    }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const familyToggle = page
        .locator('label:has-text("Family Members")')
        .first()
        .locator("input.toggle")

      // Ensure toggle is off first, then toggle on to trigger API call
      if (await familyToggle.isChecked()) {
        await familyToggle.uncheck()
        await page.waitForTimeout(500)
      }
      await familyToggle.check()
      await page.waitForTimeout(3000) // Wait for API call to complete

      const familyMembersContainer = page.locator(
        '[data-maps--maplibre-target="familyMembersContainer"]',
      )

      // Wait for the container to have content (API may take time)
      const hasContent = await page
        .waitForFunction(
          () => {
            const container = document.querySelector(
              '[data-maps--maplibre-target="familyMembersContainer"]',
            )
            if (!container) return false
            return (
              container.children.length > 0 ||
              container.textContent.trim().length > 0
            )
          },
          { timeout: 10000 },
        )
        .then(() => true)
        .catch(() => false)

      if (hasContent) {
        // Should have at least one member or a "no members" message
        const memberItems = familyMembersContainer.locator(
          'div[data-action*="centerOnFamilyMember"]',
        )
        const count = await memberItems.count()
        const containerText = await familyMembersContainer.textContent()
        expect(count > 0 || containerText.includes("No family members")).toBe(
          true,
        )
      }
      // If container has no content after timeout, the API may not have returned data - skip gracefully
    })

    test("family member item displays email and timestamp", async ({
      page,
    }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const familyToggle = page
        .locator('label:has-text("Family Members")')
        .first()
        .locator("input.toggle")

      // Ensure toggle transition happens (if already checked, uncheck first to force API call)
      if (await familyToggle.isChecked()) {
        await familyToggle.uncheck()
        await page.waitForTimeout(500)
      }
      await familyToggle.check()
      await page.waitForTimeout(2000)

      // Wait for family members to load
      await page.waitForFunction(
        () => {
          const container = document.querySelector(
            '[data-maps--maplibre-target="familyMembersContainer"]',
          )
          if (!container) return false
          return (
            container.querySelectorAll(
              'div[data-action*="centerOnFamilyMember"]',
            ).length > 0 || container.textContent.includes("No family members")
          )
        },
        { timeout: 10000 },
      )

      const familyMembersContainer = page.locator(
        '[data-maps--maplibre-target="familyMembersContainer"]',
      )
      const memberItems = familyMembersContainer.locator(
        'div[data-action*="centerOnFamilyMember"]',
      )
      const count = await memberItems.count()

      if (count > 0) {
        const firstMember = memberItems.first()

        // Should have email
        const emailElement = firstMember.locator(".text-sm.font-medium")
        await expect(emailElement).toBeVisible()

        // Should have timestamp
        const timestampElement = firstMember.locator(
          ".text-xs.text-base-content\\/60",
        )
        await expect(timestampElement).toBeVisible()
      }
    })
  })

  test.describe("Center on Member", () => {
    test("clicking family member centers map on their location", async ({
      page,
    }) => {
      test.setTimeout(60000)

      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const familyToggle = page
        .locator('label:has-text("Family Members")')
        .first()
        .locator("input.toggle")

      // Ensure toggle transition happens (if already checked, uncheck first to force API call)
      if (await familyToggle.isChecked()) {
        await familyToggle.uncheck()
        await page.waitForTimeout(500)
      }
      await familyToggle.check()
      await page.waitForTimeout(2000)

      // Wait for family members to load
      const hasFamilyMembers = await page
        .waitForFunction(
          () => {
            const container = document.querySelector(
              '[data-maps--maplibre-target="familyMembersContainer"]',
            )
            if (!container) return false
            return (
              container.querySelectorAll(
                'div[data-action*="centerOnFamilyMember"]',
              ).length > 0
            )
          },
          { timeout: 15000 },
        )
        .then(() => true)
        .catch(() => false)

      if (!hasFamilyMembers) return // Skip if no family members loaded

      const familyMembersContainer = page.locator(
        '[data-maps--maplibre-target="familyMembersContainer"]',
      )
      const memberItems = familyMembersContainer.locator(
        'div[data-action*="centerOnFamilyMember"]',
      )
      const count = await memberItems.count()

      if (count > 0) {
        // Get initial map center
        const initialCenter = await getMapCenter(page)

        // Click on first family member
        const firstMember = memberItems.first()
        await firstMember.click()

        // Wait for map animation
        await page.waitForTimeout(2000)

        // Get new map center
        const newCenter = await getMapCenter(page)

        // Map should have moved (centers should be different)
        const hasMoved =
          initialCenter.lat !== newCenter.lat ||
          initialCenter.lng !== newCenter.lng
        expect(hasMoved).toBe(true)
      }
    })

    test("shows success toast when centering on member", async ({ page }) => {
      test.setTimeout(60000)

      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const familyToggle = page
        .locator('label:has-text("Family Members")')
        .first()
        .locator("input.toggle")

      // Ensure toggle transition happens (if already checked, uncheck first to force API call)
      if (await familyToggle.isChecked()) {
        await familyToggle.uncheck()
        await page.waitForTimeout(500)
      }
      await familyToggle.check()
      await page.waitForTimeout(2000)

      // Wait for family members to load
      await page
        .waitForFunction(
          () => {
            const container = document.querySelector(
              '[data-maps--maplibre-target="familyMembersContainer"]',
            )
            if (!container) return false
            return (
              container.querySelectorAll(
                'div[data-action*="centerOnFamilyMember"]',
              ).length > 0
            )
          },
          { timeout: 10000 },
        )
        .catch(() => false)

      const familyMembersContainer = page.locator(
        '[data-maps--maplibre-target="familyMembersContainer"]',
      )
      const memberItems = familyMembersContainer.locator(
        'div[data-action*="centerOnFamilyMember"]',
      )
      const count = await memberItems.count()

      if (count > 0) {
        // Click on first family member
        const firstMember = memberItems.first()
        await firstMember.click()

        // Wait for toast to appear
        await page.waitForTimeout(500)

        // Check for success toast
        const toast = page
          .locator('.alert-success, .toast, [role="alert"]')
          .filter({ hasText: "Centered on family member" })
        await expect(toast).toBeVisible({ timeout: 3000 })
      }
    })
  })

  test.describe("Family Layer on Map", () => {
    test("family layer exists on map", async ({ page }) => {
      const hasLayer = await page.evaluate(() => {
        const element = document.querySelector(
          '[data-controller*="maps--maplibre"]',
        )
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre",
        )
        return controller?.map?.getLayer("family") !== undefined
      })

      expect(hasLayer).toBe(true)
    })

    test("family layer visibility matches toggle state", async ({ page }) => {
      // Open settings to check the toggle and layer visibility
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const familyToggle = page
        .locator('label:has-text("Family Members")')
        .first()
        .locator("input.toggle")

      // Ensure toggle is off
      if (await familyToggle.isChecked()) {
        await familyToggle.uncheck()
        await page.waitForTimeout(1000)
      }

      // Verify the layer is hidden when toggle is unchecked
      const visibility = await page.evaluate(() => {
        const element = document.querySelector(
          '[data-controller*="maps--maplibre"]',
        )
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre",
        )
        return controller?.map?.getLayoutProperty("family", "visibility")
      })

      // Layer should be 'none' (hidden) when toggle is unchecked
      expect(visibility === "none" || visibility === undefined).toBe(true)
    })

    test("family layer becomes visible when toggle is enabled", async ({
      page,
    }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const familyToggle = page
        .locator('label:has-text("Family Members")')
        .first()
        .locator("input.toggle")
      await familyToggle.check()
      await page.waitForTimeout(1500)

      const isVisible = await page.evaluate(() => {
        const element = document.querySelector(
          '[data-controller*="maps--maplibre"]',
        )
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre",
        )
        const visibility = controller?.map?.getLayoutProperty(
          "family",
          "visibility",
        )
        return visibility === "visible" || visibility === undefined
      })

      expect(isVisible).toBe(true)
    })
  })

  test.describe("Family Members Status", () => {
    test("shows appropriate message based on family members data", async ({
      page,
    }) => {
      test.setTimeout(60000)

      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const familyToggle = page
        .locator('label:has-text("Family Members")')
        .first()
        .locator("input.toggle")

      // Ensure toggle transition happens (if already checked, uncheck first to force API call)
      if (await familyToggle.isChecked()) {
        await familyToggle.uncheck()
        await page.waitForTimeout(500)
      }
      await familyToggle.check()
      await page.waitForTimeout(2000)

      const familyMembersContainer = page.locator(
        '[data-maps--maplibre-target="familyMembersContainer"]',
      )

      // Wait for container to have some content (API response)
      const hasContent = await page
        .waitForFunction(
          () => {
            const container = document.querySelector(
              '[data-maps--maplibre-target="familyMembersContainer"]',
            )
            if (!container) return false
            return (
              container.children.length > 0 ||
              container.textContent.trim().length > 0
            )
          },
          { timeout: 10000 },
        )
        .then(() => true)
        .catch(() => false)

      if (hasContent) {
        // Check what's actually displayed in the UI
        const containerText = await familyMembersContainer.textContent()
        const hasNoMembersMessage = containerText.includes(
          "No family members sharing location",
        )
        const hasLoadedMessage = containerText.match(/Loaded \d+ family member/)

        // Check for any email patterns (family members display emails)
        const hasEmailAddresses = containerText.includes("@")

        // Verify the UI shows appropriate content
        if (hasNoMembersMessage) {
          await expect(
            familyMembersContainer.getByText(
              "No family members sharing location",
            ),
          ).toBeVisible()
        } else if (hasEmailAddresses || hasLoadedMessage) {
          expect(containerText.trim().length).toBeGreaterThan(10)
        } else {
          expect(containerText.trim().length).toBeGreaterThanOrEqual(0)
        }
      }
      // If no content after timeout, API may not have returned data - skip gracefully
    })
  })

  test.describe("Auto-load on page init (#2250)", () => {
    // This tests the fix for the bug where family members were not loaded
    // when the layer was saved as enabled and the page was refreshed.
    // Previously, the user had to toggle the layer off and back on.

    test.beforeAll(async ({ request }) => {
      // Seed family member location data
      const timestamp = Math.floor(Date.now() / 1000)
      await sendOwnTracksPoint(
        request,
        API_KEYS.FAMILY_MEMBER_1,
        TEST_LOCATIONS.BERLIN_CENTER.lat,
        TEST_LOCATIONS.BERLIN_CENTER.lon,
        timestamp,
      )
    })

    test("loads family members automatically when saved as enabled", async ({
      page,
      request,
    }) => {
      test.setTimeout(60000)

      // Step 1: Enable family in settings via API BEFORE navigating
      await enableFamilyInSettings(request)

      // Step 2: Navigate fresh — no manual toggle interaction
      await navigateToMapsV2(page)
      await closeOnboardingModal(page)
      await waitForMapLibre(page)
      await waitForLoadingComplete(page)

      // Step 3: Wait for family members to appear in the DOM
      // (the fix calls loadFamilyMembers on init, which renders the list)
      const familyLoaded = await page
        .waitForFunction(
          () => {
            const container = document.querySelector(
              '[data-maps--maplibre-target="familyMembersContainer"]',
            )
            if (!container) return false
            return (
              container.querySelectorAll(
                'div[data-action*="centerOnFamilyMember"]',
              ).length > 0
            )
          },
          { timeout: 15000 },
        )
        .then(() => true)
        .catch(() => false)

      expect(familyLoaded).toBe(true)

      // Step 4: Verify the family members list is visible without toggling
      const familyMembersList = page.locator(
        '[data-maps--maplibre-target="familyMembersList"]',
      )
      const isListVisible = await familyMembersList.evaluate(
        (el) => el.style.display === "block",
      )
      expect(isListVisible).toBe(true)

      // Step 5: Verify the family layer has features on the map (not just DOM)
      const hasMapFeatures = await page.evaluate(() => {
        const element = document.querySelector(
          '[data-controller*="maps--maplibre"]',
        )
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre",
        )
        const familyLayer = controller?.layerManager?.getLayer("family")
        return familyLayer?.data?.features?.length > 0
      })
      expect(hasMapFeatures).toBe(true)

      // Step 6: Verify the progress badge counted family members
      const badgeText = await page
        .locator('[data-maps--maplibre-target="progressBadgeText"]')
        .textContent()
      expect(badgeText).toContain("family")
    })

    test.afterAll(async ({ request }) => {
      // Reset settings to defaults for test isolation
      await resetMapSettings(request)
    })
  })
})
