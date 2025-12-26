import { test, expect } from '@playwright/test'
import { closeOnboardingModal } from '../../../helpers/navigation.js'
import { navigateToMapsV2, waitForMapLibre, waitForLoadingComplete, getMapCenter } from '../../helpers/setup.js'

test.describe('Family Members Layer', () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMapsV2(page)
    await closeOnboardingModal(page)
    await waitForMapLibre(page)
    await waitForLoadingComplete(page)
    await page.waitForTimeout(1500)
  })

  test.describe('Toggle', () => {
    test('family members toggle exists in Layers tab', async ({ page }) => {
      // Open settings panel
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)

      // Click Layers tab
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      // Check if Family Members toggle exists
      const familyToggle = page.locator('label:has-text("Family Members")').first().locator('input.toggle')
      await expect(familyToggle).toBeVisible()
    })

    test('family members toggle is unchecked by default', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const familyToggle = page.locator('label:has-text("Family Members")').first().locator('input.toggle')
      const isChecked = await familyToggle.isChecked()
      expect(isChecked).toBe(false)
    })

    test('can toggle family members layer on', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const familyToggle = page.locator('label:has-text("Family Members")').first().locator('input.toggle')

      // Toggle on
      await familyToggle.check()
      await page.waitForTimeout(1000) // Wait for API call and layer update

      const isChecked = await familyToggle.isChecked()
      expect(isChecked).toBe(true)
    })

    test('can toggle family members layer off', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const familyToggle = page.locator('label:has-text("Family Members")').first().locator('input.toggle')

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

  test.describe('Family Members List', () => {
    test('family members list is hidden by default', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const familyMembersList = page.locator('[data-maps--maplibre-target="familyMembersList"]')

      // Should be hidden initially
      const isHidden = await familyMembersList.evaluate(el => el.style.display === 'none')
      expect(isHidden).toBe(true)
    })

    test('family members list appears when toggle is enabled', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const familyToggle = page.locator('label:has-text("Family Members")').first().locator('input.toggle')
      const familyMembersList = page.locator('[data-maps--maplibre-target="familyMembersList"]')

      // Toggle on
      await familyToggle.check()
      await page.waitForTimeout(1000)

      // List should now be visible
      const isVisible = await familyMembersList.evaluate(el => el.style.display === 'block')
      expect(isVisible).toBe(true)
    })

    test('family members list shows members when data exists', async ({ page }) => {
      // Skip if no family members exist
      const hasFamilyMembers = await page.evaluate(async () => {
        const apiKey = document.querySelector('[data-maps--maplibre-api-key-value]')?.dataset.mapsMaplibreApiKeyValue
        if (!apiKey) return false

        try {
          const response = await fetch(`/api/v1/families/locations?api_key=${apiKey}`)
          if (!response.ok) return false
          const data = await response.json()
          return data.locations && data.locations.length > 0
        } catch (error) {
          return false
        }
      })

      if (!hasFamilyMembers) {
        test.skip()
        return
      }

      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const familyToggle = page.locator('label:has-text("Family Members")').first().locator('input.toggle')

      // Toggle on
      await familyToggle.check()
      await page.waitForTimeout(1500) // Wait for API call

      const familyMembersContainer = page.locator('[data-maps--maplibre-target="familyMembersContainer"]')

      // Should have at least one member
      const memberItems = familyMembersContainer.locator('div[data-action*="centerOnFamilyMember"]')
      const count = await memberItems.count()
      expect(count).toBeGreaterThan(0)
    })

    test('family member item displays email and timestamp', async ({ page }) => {
      // Skip if no family members exist
      const hasFamilyMembers = await page.evaluate(async () => {
        const apiKey = document.querySelector('[data-maps--maplibre-api-key-value]')?.dataset.mapsMaplibreApiKeyValue
        if (!apiKey) return false

        try {
          const response = await fetch(`/api/v1/families/locations?api_key=${apiKey}`)
          if (!response.ok) return false
          const data = await response.json()
          return data.locations && data.locations.length > 0
        } catch (error) {
          return false
        }
      })

      if (!hasFamilyMembers) {
        test.skip()
        return
      }

      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const familyToggle = page.locator('label:has-text("Family Members")').first().locator('input.toggle')
      await familyToggle.check()
      await page.waitForTimeout(1500)

      const familyMembersContainer = page.locator('[data-maps--maplibre-target="familyMembersContainer"]')
      const firstMember = familyMembersContainer.locator('div[data-action*="centerOnFamilyMember"]').first()

      // Should have email
      const emailElement = firstMember.locator('.text-sm.font-medium')
      await expect(emailElement).toBeVisible()

      // Should have timestamp
      const timestampElement = firstMember.locator('.text-xs.text-base-content\\/60')
      await expect(timestampElement).toBeVisible()
    })
  })

  test.describe('Center on Member', () => {
    test('clicking family member centers map on their location', async ({ page }) => {
      // Skip if no family members exist
      const hasFamilyMembers = await page.evaluate(async () => {
        const apiKey = document.querySelector('[data-maps--maplibre-api-key-value]')?.dataset.mapsMaplibreApiKeyValue
        if (!apiKey) return false

        try {
          const response = await fetch(`/api/v1/families/locations?api_key=${apiKey}`)
          if (!response.ok) return false
          const data = await response.json()
          return data.locations && data.locations.length > 0
        } catch (error) {
          return false
        }
      })

      if (!hasFamilyMembers) {
        test.skip()
        return
      }

      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const familyToggle = page.locator('label:has-text("Family Members")').first().locator('input.toggle')
      await familyToggle.check()
      await page.waitForTimeout(1500)

      // Get initial map center
      const initialCenter = await getMapCenter(page)

      // Click on first family member
      const familyMembersContainer = page.locator('[data-maps--maplibre-target="familyMembersContainer"]')
      const firstMember = familyMembersContainer.locator('div[data-action*="centerOnFamilyMember"]').first()
      await firstMember.click()

      // Wait for map animation
      await page.waitForTimeout(2000)

      // Get new map center
      const newCenter = await getMapCenter(page)

      // Map should have moved (centers should be different)
      const hasMoved = initialCenter.lat !== newCenter.lat || initialCenter.lng !== newCenter.lng
      expect(hasMoved).toBe(true)
    })

    test('shows success toast when centering on member', async ({ page }) => {
      // Skip if no family members exist
      const hasFamilyMembers = await page.evaluate(async () => {
        const apiKey = document.querySelector('[data-maps--maplibre-api-key-value]')?.dataset.mapsMaplibreApiKeyValue
        if (!apiKey) return false

        try {
          const response = await fetch(`/api/v1/families/locations?api_key=${apiKey}`)
          if (!response.ok) return false
          const data = await response.json()
          return data.locations && data.locations.length > 0
        } catch (error) {
          return false
        }
      })

      if (!hasFamilyMembers) {
        test.skip()
        return
      }

      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const familyToggle = page.locator('label:has-text("Family Members")').first().locator('input.toggle')
      await familyToggle.check()
      await page.waitForTimeout(1500)

      // Click on first family member
      const familyMembersContainer = page.locator('[data-maps--maplibre-target="familyMembersContainer"]')
      const firstMember = familyMembersContainer.locator('div[data-action*="centerOnFamilyMember"]').first()
      await firstMember.click()

      // Wait for toast to appear
      await page.waitForTimeout(500)

      // Check for success toast
      const toast = page.locator('.alert-success, .toast, [role="alert"]').filter({ hasText: 'Centered on family member' })
      await expect(toast).toBeVisible({ timeout: 3000 })
    })
  })

  test.describe('Family Layer on Map', () => {
    test('family layer exists on map', async ({ page }) => {
      const hasLayer = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller?.map?.getLayer('family') !== undefined
      })

      expect(hasLayer).toBe(true)
    })

    test('family layer is hidden by default', async ({ page }) => {
      const isVisible = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const visibility = controller?.map?.getLayoutProperty('family', 'visibility')
        return visibility === 'visible'
      })

      expect(isVisible).toBe(false)
    })

    test('family layer becomes visible when toggle is enabled', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const familyToggle = page.locator('label:has-text("Family Members")').first().locator('input.toggle')
      await familyToggle.check()
      await page.waitForTimeout(1500)

      const isVisible = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const visibility = controller?.map?.getLayoutProperty('family', 'visibility')
        return visibility === 'visible' || visibility === undefined
      })

      expect(isVisible).toBe(true)
    })
  })

  test.describe('No Family Members', () => {
    test('shows appropriate message when no family members are sharing', async ({ page }) => {
      // This test checks the message when API returns empty array
      const hasFamilyMembers = await page.evaluate(async () => {
        const apiKey = document.querySelector('[data-maps--maplibre-api-key-value]')?.dataset.mapsMaplibreApiKeyValue
        if (!apiKey) return false

        try {
          const response = await fetch(`/api/v1/families/locations?api_key=${apiKey}`)
          if (!response.ok) return false
          const data = await response.json()
          return data.locations && data.locations.length > 0
        } catch (error) {
          return false
        }
      })

      // Only run this test if there are NO family members
      if (hasFamilyMembers) {
        test.skip()
        return
      }

      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const familyToggle = page.locator('label:has-text("Family Members")').first().locator('input.toggle')
      await familyToggle.check()
      await page.waitForTimeout(1500)

      const familyMembersContainer = page.locator('[data-maps--maplibre-target="familyMembersContainer"]')
      const noMembersMessage = familyMembersContainer.getByText('No family members sharing location')

      await expect(noMembersMessage).toBeVisible()
    })
  })
})
