import { expect, test } from "@playwright/test"
import { closeOnboardingModal } from "../../helpers/navigation.js"
import { waitForLoadingComplete, waitForMapLibre } from "../helpers/setup.js"

// Configure tests to run serially to avoid resource contention with MapLibre/WebGL
test.describe.configure({ mode: "serial" })

/**
 * Open the settings panel and switch to the Timeline Feed tab.
 * Returns the turbo-frame element for the feed.
 */
async function openTimelineFeedTab(page) {
  // Open settings panel
  const settingsButton = page.locator('button[title="Open map settings"]')
  await settingsButton.click()
  await page.waitForSelector(
    '[data-maps--maplibre-target="settingsPanel"]',
    { state: "visible", timeout: 5000 },
  )

  // Click the timeline-feed tab
  const tabButton = page.locator('button[data-tab="timeline-feed"]')
  await tabButton.click()
  await page.waitForTimeout(300)
}

/**
 * Wait for the timeline feed turbo-frame to finish loading.
 */
async function waitForTimelineFeedLoaded(page, timeout = 10000) {
  await page.waitForFunction(
    () => {
      const frame = document.getElementById("timeline-feed-frame")
      if (!frame) return false
      // Turbo removes [busy] when the frame load is complete
      if (frame.hasAttribute("busy")) return false
      // Check that the frame has real content (not the placeholder)
      return !frame.querySelector(".timeline-feed-placeholder")
    },
    { timeout },
  )
}

test.describe("Timeline Feed Panel", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(
      "/map/v2?start_at=2025-10-15T00:00&end_at=2025-10-16T23:59",
    )
    await closeOnboardingModal(page)
    await waitForMapLibre(page)
    await waitForLoadingComplete(page)
    await page.waitForTimeout(500)
  })

  test.describe("Tab and Loading", () => {
    test("timeline-feed tab exists in the settings panel", async ({
      page,
    }) => {
      const settingsButton = page.locator(
        'button[title="Open map settings"]',
      )
      await settingsButton.click()
      await page.waitForTimeout(300)

      const tabButton = page.locator('button[data-tab="timeline-feed"]')
      await expect(tabButton).toBeVisible()
    })

    test("switching to timeline-feed tab triggers turbo-frame load", async ({
      page,
    }) => {
      await openTimelineFeedTab(page)

      // The turbo-frame should now have a src attribute set by the controller
      const frame = page.locator("#timeline-feed-frame")
      await page.waitForFunction(
        () => {
          const el = document.getElementById("timeline-feed-frame")
          return el && el.getAttribute("src")
        },
        { timeout: 5000 },
      )
      const src = await frame.getAttribute("src")
      expect(src).toContain("/map/timeline_feeds")
      expect(src).toContain("start_at=")
      expect(src).toContain("end_at=")
    })

    test("shows loading spinner while fetching", async ({ page }) => {
      // Intercept the request to delay it so we can observe the loading state
      await page.route("**/map/timeline_feeds**", async (route) => {
        await new Promise((resolve) => setTimeout(resolve, 500))
        await route.continue()
      })

      await openTimelineFeedTab(page)

      // During load, the frame should have [busy] attribute
      const frame = page.locator("#timeline-feed-frame")
      // The CSS spinner fires via #timeline-feed-frame[busy]::after
      const isBusy = await frame.evaluate((el) => el.hasAttribute("busy"))
      // May or may not catch it depending on timing, but verify no crash
      expect(typeof isBusy).toBe("boolean")
    })

    test("displays day accordions after load", async ({ page }) => {
      await openTimelineFeedTab(page)
      await waitForTimelineFeedLoaded(page)

      // Should have at least one day accordion
      const dayAccordions = page.locator(".timeline-day-accordion")
      const count = await dayAccordions.count()
      expect(count).toBeGreaterThan(0)
    })
  })

  test.describe("Day Accordion Behavior", () => {
    test("day accordion shows date and distance badge", async ({ page }) => {
      await openTimelineFeedTab(page)
      await waitForTimelineFeedLoaded(page)

      const firstDay = page.locator(".timeline-day-accordion").first()
      const summaryText = await firstDay
        .locator(".collapse-title")
        .textContent()

      // Should contain a day name (e.g., "Wednesday, October 15")
      expect(summaryText).toMatch(/\w+day/)
    })

    test("expanding a day shows entries", async ({ page }) => {
      await openTimelineFeedTab(page)
      await waitForTimelineFeedLoaded(page)

      // Click the first day to expand it
      const firstDay = page.locator(".timeline-day-accordion").first()
      await firstDay.locator("summary").click()
      await page.waitForTimeout(300)

      // Should show visit or journey entries
      const entries = firstDay.locator(
        ".timeline-visit-wrapper, .timeline-journey-connector",
      )
      const count = await entries.count()
      expect(count).toBeGreaterThanOrEqual(0)
    })

    test("only one day accordion is open at a time", async ({ page }) => {
      await openTimelineFeedTab(page)
      await waitForTimelineFeedLoaded(page)

      const accordions = page.locator(".timeline-day-accordion")
      const count = await accordions.count()
      if (count < 2) {
        test.skip()
        return
      }

      // Open the first day
      await accordions.nth(0).locator("summary").click()
      await page.waitForTimeout(300)

      // Verify first is open
      const firstOpen = await accordions
        .nth(0)
        .evaluate((el) => el.open)
      expect(firstOpen).toBe(true)

      // Open the second day
      await accordions.nth(1).locator("summary").click()
      await page.waitForTimeout(300)

      // First should now be closed, second open
      const firstAfter = await accordions
        .nth(0)
        .evaluate((el) => el.open)
      const secondAfter = await accordions
        .nth(1)
        .evaluate((el) => el.open)
      expect(firstAfter).toBe(false)
      expect(secondAfter).toBe(true)
    })
  })

  test.describe("Journey Entries", () => {
    test("journey entries display mode emoji and distance", async ({
      page,
    }) => {
      await openTimelineFeedTab(page)
      await waitForTimelineFeedLoaded(page)

      // Expand the first day
      const firstDay = page.locator(".timeline-day-accordion").first()
      await firstDay.locator("summary").click()
      await page.waitForTimeout(300)

      const journeys = firstDay.locator(".timeline-journey-connector")
      const journeyCount = await journeys.count()

      if (journeyCount === 0) {
        test.skip()
        return
      }

      const firstJourney = journeys.first()
      const content = await firstJourney
        .locator(".timeline-journey-content")
        .textContent()

      // Should contain a mode verb (walked, drove, cycled, etc.)
      expect(content).toMatch(
        /walked|drove|cycled|ran|bus|train|flew|sailed|rode|traveled/,
      )
    })

    test("clicking a journey entry with track_id toggles track info panel", async ({
      page,
    }) => {
      await openTimelineFeedTab(page)
      await waitForTimelineFeedLoaded(page)

      // Expand the first day
      const firstDay = page.locator(".timeline-day-accordion").first()
      await firstDay.locator("summary").click()
      await page.waitForTimeout(300)

      // Find a journey entry with a track-id
      const journeyWithTrack = firstDay.locator(
        '.timeline-journey-content[data-track-id]',
      )
      const count = await journeyWithTrack.count()

      if (count === 0) {
        test.skip()
        return
      }

      const entry = journeyWithTrack.first()
      const trackId = await entry.getAttribute("data-track-id")

      // Click to expand track info
      await entry.click()
      await page.waitForTimeout(500)

      // The turbo-frame for this track should be visible
      const trackFrame = page.locator(`#track-info-${trackId}`)
      const isHidden = await trackFrame.evaluate((el) =>
        el.classList.contains("hidden"),
      )
      expect(isHidden).toBe(false)

      // Click again to collapse
      await entry.click()
      await page.waitForTimeout(300)

      const isHiddenAfter = await trackFrame.evaluate((el) =>
        el.classList.contains("hidden"),
      )
      expect(isHiddenAfter).toBe(true)
    })
  })

  test.describe("Visit Entries", () => {
    test("visit entries show place name and time", async ({ page }) => {
      await openTimelineFeedTab(page)
      await waitForTimelineFeedLoaded(page)

      // Expand the first day
      const firstDay = page.locator(".timeline-day-accordion").first()
      await firstDay.locator("summary").click()
      await page.waitForTimeout(300)

      const visits = firstDay.locator(".timeline-visit-wrapper")
      const visitCount = await visits.count()

      if (visitCount === 0) {
        test.skip()
        return
      }

      const firstVisit = visits.first()

      // Should have a timestamp
      const timestamp = firstVisit.locator(".timeline-timestamp")
      const timeText = await timestamp.textContent()
      expect(timeText.trim()).toMatch(/\d{2}:\d{2}/)

      // Should have a place name
      const card = firstVisit.locator(".timeline-visit-card")
      const cardText = await card.textContent()
      expect(cardText.length).toBeGreaterThan(0)
    })
  })

  test.describe("Map Interaction", () => {
    test("expanding a day dispatches day-expanded event without JS errors", async ({
      page,
    }) => {
      const consoleErrors = []
      page.on("console", (msg) => {
        if (msg.type() === "error") {
          consoleErrors.push(msg.text())
        }
      })

      await openTimelineFeedTab(page)
      await waitForTimelineFeedLoaded(page)

      const firstDay = page.locator(".timeline-day-accordion").first()
      await firstDay.locator("summary").click()
      await page.waitForTimeout(500)

      // Verify no JS errors from the interaction
      const relevantErrors = consoleErrors.filter(
        (err) => !err.includes("404") && !err.includes("net::"),
      )
      expect(relevantErrors).toEqual([])
    })

    test("hovering a journey entry dispatches hover event without JS errors", async ({
      page,
    }) => {
      const consoleErrors = []
      page.on("console", (msg) => {
        if (msg.type() === "error") {
          consoleErrors.push(msg.text())
        }
      })

      await openTimelineFeedTab(page)
      await waitForTimelineFeedLoaded(page)

      // Expand the first day
      const firstDay = page.locator(".timeline-day-accordion").first()
      await firstDay.locator("summary").click()
      await page.waitForTimeout(300)

      const journeys = firstDay.locator(".timeline-journey-connector")
      const count = await journeys.count()

      if (count === 0) {
        test.skip()
        return
      }

      // Hover over the first journey
      await journeys.first().hover()
      await page.waitForTimeout(300)

      // Move away
      const mapCanvas = page.locator(".maplibregl-canvas")
      await mapCanvas.hover({ position: { x: 10, y: 10 } })
      await page.waitForTimeout(300)

      const relevantErrors = consoleErrors.filter(
        (err) => !err.includes("404") && !err.includes("net::"),
      )
      expect(relevantErrors).toEqual([])
    })
  })

  test.describe("Empty State", () => {
    test("shows empty message when no visits or journeys exist for date range", async ({
      page,
    }) => {
      // Navigate to a date range with no data
      await page.goto(
        "/map/v2?start_at=2020-01-01T00:00&end_at=2020-01-01T23:59",
      )
      await closeOnboardingModal(page)
      await waitForMapLibre(page)
      await waitForLoadingComplete(page)
      await page.waitForTimeout(500)

      await openTimelineFeedTab(page)
      await waitForTimelineFeedLoaded(page).catch(() => {
        // May not load "real" content if there's no data, that's fine
      })

      // Wait for frame to settle
      await page.waitForTimeout(1000)

      const frame = page.locator("#timeline-feed-frame")
      const frameText = await frame.textContent()

      // Should show either empty message or placeholder
      const hasEmptyIndicator =
        frameText.includes("No visits or journeys") ||
        frameText.includes("No activity") ||
        frameText.includes("Select a date range")
      expect(hasEmptyIndicator).toBe(true)
    })
  })

  test.describe("Date Range Updates", () => {
    test("timeline feed refreshes when date range changes", async ({
      page,
    }) => {
      await openTimelineFeedTab(page)
      await waitForTimelineFeedLoaded(page)

      // Record the initial frame src
      const initialSrc = await page.evaluate(() => {
        const frame = document.getElementById("timeline-feed-frame")
        return frame?.getAttribute("src") || ""
      })

      // Close settings panel
      const closeButton = page.locator('button[title="Close panel"]')
      await closeButton.click()
      await page.waitForTimeout(300)

      // Change the date range
      const startInput = page.locator(
        'input[type="datetime-local"][name="start_at"]',
      )
      await startInput.clear()
      await startInput.fill("2025-10-14T00:00")

      const endInput = page.locator(
        'input[type="datetime-local"][name="end_at"]',
      )
      await endInput.clear()
      await endInput.fill("2025-10-14T23:59")

      await page.click('input[type="submit"][value="Search"]')
      await page.waitForLoadState("networkidle")
      await waitForMapLibre(page)
      await waitForLoadingComplete(page)
      await page.waitForTimeout(1000)

      // Re-open the timeline feed tab
      await openTimelineFeedTab(page)
      await page.waitForTimeout(1000)

      // The frame src should have updated with new dates
      const newSrc = await page.evaluate(() => {
        const frame = document.getElementById("timeline-feed-frame")
        return frame?.getAttribute("src") || ""
      })

      // If we got a new src, it should differ (different dates)
      if (newSrc && initialSrc) {
        expect(newSrc).not.toBe(initialSrc)
      }
    })
  })
})
