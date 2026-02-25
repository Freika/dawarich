import { expect, test } from "@playwright/test"
import { waitForMap } from "../helpers/map.js"
import { navigateToMap } from "../helpers/navigation.js"

test.describe("Places Creation", () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMap(page)
    await waitForMap(page)
  })

  test('should enable place creation mode when "Create a place" button is clicked', async ({
    page,
  }) => {
    const createPlaceBtn = page.locator("#create-place-btn")

    // Verify button exists
    await expect(createPlaceBtn).toBeVisible()

    // Click to enable creation mode
    await createPlaceBtn.click()
    await page.waitForTimeout(300)

    // Verify creation mode is enabled
    const isCreationMode = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(
        (c) => c.identifier === "maps",
      )
      return controller?.placesManager?.creationMode === true
    })

    expect(isCreationMode).toBe(true)
  })

  test("should change button icon to X when in place creation mode", async ({
    page,
  }) => {
    const createPlaceBtn = page.locator("#create-place-btn")

    // Click to enable creation mode
    await createPlaceBtn.click()
    await page.waitForTimeout(300)

    // Verify button tooltip changed
    const tooltip = await createPlaceBtn.getAttribute("data-tip")
    expect(tooltip).toContain("click to cancel")

    // Verify button has active state
    const hasActiveClass = await createPlaceBtn.evaluate((btn) => {
      return (
        btn.classList.contains("active") ||
        btn.style.backgroundColor !== "" ||
        btn.hasAttribute("data-active")
      )
    })

    expect(hasActiveClass).toBe(true)
  })

  test("should exit place creation mode when X button is clicked", async ({
    page,
  }) => {
    const createPlaceBtn = page.locator("#create-place-btn")

    // Enable creation mode
    await createPlaceBtn.click()
    await page.waitForTimeout(300)

    // Click again to disable
    await createPlaceBtn.click()
    await page.waitForTimeout(300)

    // Verify creation mode is disabled
    const isCreationMode = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(
        (c) => c.identifier === "maps",
      )
      return controller?.placesManager?.creationMode === true
    })

    expect(isCreationMode).toBe(false)
  })

  test("should open place creation popup when map is clicked in creation mode", async ({
    page,
  }) => {
    const createPlaceBtn = page.locator("#create-place-btn")

    // Enable creation mode
    await createPlaceBtn.click()
    await page.waitForTimeout(300)

    // Get map container and click on it
    const mapContainer = page.locator("#map")
    await mapContainer.click({ position: { x: 300, y: 300 } })
    await page.waitForTimeout(500)

    // Verify modal is open
    const modalOpen = await page
      .locator('[data-place-creation-target="modal"]')
      .evaluate((modal) => {
        return modal.classList.contains("modal-open")
      })

    expect(modalOpen).toBe(true)

    // Verify form fields exist (latitude/longitude are hidden inputs, so we check they exist, not visibility)
    await expect(
      page.locator('[data-place-creation-target="nameInput"]'),
    ).toBeVisible()
    await expect(
      page.locator('[data-place-creation-target="latitudeInput"]'),
    ).toBeAttached()
    await expect(
      page.locator('[data-place-creation-target="longitudeInput"]'),
    ).toBeAttached()
  })

  test("should allow user to provide name, notes and select tags in creation popup", async ({
    page,
  }) => {
    const createPlaceBtn = page.locator("#create-place-btn")

    // Enable creation mode
    await createPlaceBtn.click()
    await page.waitForTimeout(300)

    // Click on map
    const mapContainer = page.locator("#map")
    await mapContainer.click({ position: { x: 300, y: 300 } })
    await page.waitForTimeout(500)

    // Fill in the form
    const nameInput = page.locator('[data-place-creation-target="nameInput"]')
    await nameInput.fill("Test Place")

    const noteInput = page.locator('textarea[name="note"]')
    if (await noteInput.isVisible()) {
      await noteInput.fill("This is a test note")
    }

    // Check if there are any tag checkboxes to select
    const tagCheckboxes = page.locator('input[name="tag_ids[]"]')
    const tagCount = await tagCheckboxes.count()
    if (tagCount > 0) {
      await tagCheckboxes.first().check()
    }

    // Verify fields are filled
    await expect(nameInput).toHaveValue("Test Place")
  })

  test("should save place when Save button is clicked @destructive", async ({
    page,
  }) => {
    const createPlaceBtn = page.locator("#create-place-btn")

    // Enable creation mode
    await createPlaceBtn.click()
    await page.waitForTimeout(300)

    // Click on map
    const mapContainer = page.locator("#map")
    await mapContainer.click({ position: { x: 300, y: 300 } })
    await page.waitForTimeout(500)

    // Fill in the form with a unique name
    const placeName = `E2E Test Place ${Date.now()}`
    const nameInput = page.locator('[data-place-creation-target="nameInput"]')
    await nameInput.fill(placeName)

    // Submit form
    const submitBtn = page.locator(
      '[data-place-creation-target="form"] button[type="submit"]',
    )

    // Set up a promise to wait for the place:created event
    const placeCreatedPromise = page.evaluate(() => {
      return new Promise((resolve) => {
        document.addEventListener(
          "place:created",
          (e) => {
            resolve(e.detail)
          },
          { once: true },
        )
      })
    })

    await submitBtn.click()

    // Wait for the place to be created
    await placeCreatedPromise

    // Verify modal is closed
    await page.waitForTimeout(500)
    const modalOpen = await page
      .locator('[data-place-creation-target="modal"]')
      .evaluate((modal) => {
        return modal.classList.contains("modal-open")
      })

    expect(modalOpen).toBe(false)

    // Verify success message is shown
    const hasSuccessMessage = await page.evaluate(() => {
      const flashMessages = document.querySelectorAll(
        '.alert, .flash, [role="alert"]',
      )
      return Array.from(flashMessages).some(
        (msg) =>
          msg.textContent.includes("success") ||
          msg.classList.contains("alert-success"),
      )
    })

    expect(hasSuccessMessage).toBe(true)
  })

  test("should put clickable marker on map after saving place @destructive", async ({
    page,
  }) => {
    const createPlaceBtn = page.locator("#create-place-btn")

    // Enable creation mode
    await createPlaceBtn.click()
    await page.waitForTimeout(300)

    // Click on map
    const mapContainer = page.locator("#map")
    await mapContainer.click({ position: { x: 300, y: 300 } })
    await page.waitForTimeout(500)

    // Fill and submit form
    const placeName = `E2E Test Place ${Date.now()}`
    await page
      .locator('[data-place-creation-target="nameInput"]')
      .fill(placeName)

    const placeCreatedPromise = page.evaluate(() => {
      return new Promise((resolve) => {
        document.addEventListener(
          "place:created",
          (e) => {
            resolve(e.detail)
          },
          { once: true },
        )
      })
    })

    await page
      .locator('[data-place-creation-target="form"] button[type="submit"]')
      .click()
    await placeCreatedPromise
    await page.waitForTimeout(1000)

    // Verify marker was added to the map
    const hasMarker = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(
        (c) => c.identifier === "maps",
      )
      const placesLayer = controller?.placesManager?.placesLayer

      if (!placesLayer || !placesLayer._layers) {
        return false
      }

      return Object.keys(placesLayer._layers).length > 0
    })

    expect(hasMarker).toBe(true)
  })

  test("should close popup and remove marker when Cancel is clicked", async ({
    page,
  }) => {
    const createPlaceBtn = page.locator("#create-place-btn")

    // Enable creation mode
    await createPlaceBtn.click()
    await page.waitForTimeout(300)

    // Click on map
    const mapContainer = page.locator("#map")
    await mapContainer.click({ position: { x: 300, y: 300 } })
    await page.waitForTimeout(500)

    // Check if creation marker exists
    const hasCreationMarkerBefore = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(
        (c) => c.identifier === "maps",
      )
      return controller?.placesManager?.creationMarker !== null
    })

    expect(hasCreationMarkerBefore).toBe(true)

    // Click cancel
    const cancelBtn = page
      .locator('[data-place-creation-target="modal"] button')
      .filter({ hasText: /cancel|close/i })
      .first()
    await cancelBtn.click()
    await page.waitForTimeout(500)

    // Verify modal is closed
    const modalOpen = await page
      .locator('[data-place-creation-target="modal"]')
      .evaluate((modal) => {
        return modal.classList.contains("modal-open")
      })

    expect(modalOpen).toBe(false)

    // Verify creation marker is removed
    const hasCreationMarkerAfter = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(
        (c) => c.identifier === "maps",
      )
      return controller?.placesManager?.creationMarker !== null
    })

    expect(hasCreationMarkerAfter).toBe(false)
  })

  test("should close previous popup and open new one when clicking different location", async ({
    page,
  }) => {
    const createPlaceBtn = page.locator("#create-place-btn")

    // Enable creation mode
    await createPlaceBtn.click()
    await page.waitForTimeout(300)

    // Click first location
    const mapContainer = page.locator("#map")
    await mapContainer.click({ position: { x: 300, y: 300 } })
    await page.waitForTimeout(500)

    // Get first coordinates
    const firstCoords = await page.evaluate(() => {
      const latInput = document.querySelector(
        '[data-place-creation-target="latitudeInput"]',
      )
      const lngInput = document.querySelector(
        '[data-place-creation-target="longitudeInput"]',
      )
      return {
        lat: latInput?.value,
        lng: lngInput?.value,
      }
    })

    // Verify first coordinates exist
    expect(firstCoords.lat).toBeTruthy()
    expect(firstCoords.lng).toBeTruthy()

    // Use programmatic click to simulate clicking on a different map location
    // This bypasses UI interference with modal
    const secondCoords = await page.evaluate(() => {
      const controller = window.Stimulus?.controllers.find(
        (c) => c.identifier === "maps",
      )
      if (controller?.placesManager?.creationMode) {
        // Simulate clicking at a different location
        const map = controller.map
        const center = map.getCenter()
        const newLatlng = { lat: center.lat + 0.01, lng: center.lng + 0.01 }

        // Trigger place creation at new location
        controller.placesManager.handleMapClick({ latlng: newLatlng })

        // Wait for UI update
        return new Promise((resolve) => {
          setTimeout(() => {
            const latInput = document.querySelector(
              '[data-place-creation-target="latitudeInput"]',
            )
            const lngInput = document.querySelector(
              '[data-place-creation-target="longitudeInput"]',
            )
            resolve({
              lat: latInput?.value,
              lng: lngInput?.value,
            })
          }, 100)
        })
      }
      return null
    })

    // Verify second coordinates exist and are different from first
    expect(secondCoords).toBeTruthy()
    expect(secondCoords.lat).toBeTruthy()
    expect(secondCoords.lng).toBeTruthy()
    expect(firstCoords.lat).not.toBe(secondCoords.lat)
    expect(firstCoords.lng).not.toBe(secondCoords.lng)

    // Verify modal is still open
    const modalOpen = await page
      .locator('[data-place-creation-target="modal"]')
      .evaluate((modal) => {
        return modal.classList.contains("modal-open")
      })

    expect(modalOpen).toBe(true)
  })
})
