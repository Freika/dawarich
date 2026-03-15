/**
 * Places helper functions for Playwright tests
 */

/**
 * Enable or disable the Places layer
 * @param {Page} page - Playwright page object
 * @param {boolean} enable - True to enable, false to disable
 */
export async function enablePlacesLayer(page, enable) {
  // Wait a bit for Places control to potentially be created
  await page.waitForTimeout(500)

  // Check if Places control button exists
  const placesControlBtn = page.locator(".leaflet-control-places-button")
  const hasPlacesControl = (await placesControlBtn.count()) > 0

  if (hasPlacesControl) {
    // Use Places control panel
    const placesPanel = page.locator(".leaflet-control-places-panel")
    const isPanelVisible = await placesPanel
      .evaluate((el) => {
        return el.style.display !== "none" && el.offsetParent !== null
      })
      .catch(() => false)

    // Open panel if not visible
    if (!isPanelVisible) {
      await placesControlBtn.click()
      await page.waitForTimeout(300)
    }

    // Toggle the "Show All Places" checkbox
    const allPlacesCheckbox = page.locator('[data-filter="all"]')

    if (await allPlacesCheckbox.isVisible()) {
      const isChecked = await allPlacesCheckbox.isChecked()

      if (enable && !isChecked) {
        await allPlacesCheckbox.check()
        await page.waitForTimeout(1000)
      } else if (!enable && isChecked) {
        await allPlacesCheckbox.uncheck()
        await page.waitForTimeout(500)
      }
    }
  } else {
    // Fallback: Use Leaflet's layer control
    await page.locator(".leaflet-control-layers").hover()
    await page.waitForTimeout(300)

    const placesLayerCheckbox = page
      .locator(".leaflet-control-layers-overlays label")
      .filter({ hasText: "Places" })
      .locator('input[type="checkbox"]')

    if ((await placesLayerCheckbox.count()) > 0) {
      const isChecked = await placesLayerCheckbox.isChecked()

      if (enable && !isChecked) {
        await placesLayerCheckbox.check()
        await page.waitForTimeout(1000)
      } else if (!enable && isChecked) {
        await placesLayerCheckbox.uncheck()
        await page.waitForTimeout(500)
      }
    }
  }
}

/**
 * Check if the Places layer is currently visible on the map
 * @param {Page} page - Playwright page object
 * @returns {Promise<boolean>} - True if Places layer is visible
 */
export async function getPlacesLayerVisible(page) {
  return await page.evaluate(() => {
    const controller = window.Stimulus?.controllers.find(
      (c) => c.identifier === "maps",
    )
    const placesLayer = controller?.placesManager?.placesLayer

    if (!placesLayer || !controller?.map) {
      return false
    }

    return controller.map.hasLayer(placesLayer)
  })
}

/**
 * Create a test place programmatically
 * @param {Page} page - Playwright page object
 * @param {string} name - Name of the place
 * @param {number} latitude - Latitude coordinate
 * @param {number} longitude - Longitude coordinate
 */
export async function createTestPlace(page, name, latitude, longitude) {
  // Enable place creation mode
  const createPlaceBtn = page.locator("#create-place-btn")
  await createPlaceBtn.click()
  await page.waitForTimeout(300)

  // Simulate map click to open the creation popup
  const mapContainer = page.locator("#map")
  await mapContainer.click({ position: { x: 300, y: 300 } })
  await page.waitForTimeout(500)

  // Fill in the form
  const nameInput = page.locator('[data-place-creation-target="nameInput"]')
  await nameInput.fill(name)

  // Set coordinates manually (overriding the auto-filled values from map click)
  await page.evaluate(
    ({ lat, lng }) => {
      const latInput = document.querySelector(
        '[data-place-creation-target="latitudeInput"]',
      )
      const lngInput = document.querySelector(
        '[data-place-creation-target="longitudeInput"]',
      )
      if (latInput) latInput.value = lat.toString()
      if (lngInput) lngInput.value = lng.toString()
    },
    { lat: latitude, lng: longitude },
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

  // Submit the form
  const submitBtn = page.locator(
    '[data-place-creation-target="form"] button[type="submit"]',
  )
  await submitBtn.click()

  // Wait for the place to be created
  await placeCreatedPromise
  await page.waitForTimeout(500)
}
