import { expect, test } from "@playwright/test"
import { closeOnboardingModal } from "./helpers/navigation.js"
import { waitForMapLibre, waitForStudioReady } from "./v2/helpers/setup.js"
import {
  selectCalendarDay,
  waitForCalendarLoaded,
} from "./v2/helpers/timeline.js"

async function map(page) {
  await page.goto(
    "/map/v2?start_at=2020-02-03T00:00:00&end_at=2020-02-03T23:59:59&panel=timeline&date=2020-02-03",
  )
  expect(new URL(page.url()).pathname).toBe("/map/v2")
  await closeOnboardingModal(page)
  await waitForMapLibre(page)
  await expect
    .poll(() => page.evaluate(() => window.liveSocket.main?.isConnected()))
    .toBe(true)
  await waitForCalendarLoaded(page)
}

test("Back and Forward disconnect the old map and both body studios", async ({
  page,
}) => {
  await map(page)
  for (const [id, identifier] of [
    ["poster-studio", "poster-studio-editor"],
    ["video-studio", "video-studio"],
  ]) {
    await waitForStudioReady(page, id, identifier)
  }
  await page.evaluate(() => {
    window.__a6DocumentMarker = "same-document-history"
    window.__a6OldRoot = document.getElementById("map-shell")
    window.__a6OldApp = window.Stimulus
    window.__a6Disconnected = {}
    for (const [id, identifier] of [
      ["maps-maplibre-container", "maps--maplibre"],
      ["poster-studio", "poster-studio-editor"],
      ["video-studio", "video-studio"],
    ]) {
      const controller = window.Stimulus.getControllerForElementAndIdentifier(
        document.getElementById(id),
        identifier,
      )
      const disconnect = controller.disconnect.bind(controller)
      controller.disconnect = () => {
        window.__a6Disconnected[identifier] =
          (window.__a6Disconnected[identifier] || 0) + 1
        return disconnect()
      }
    }
  })
  await selectCalendarDay(page, "2020-02-10")
  await selectCalendarDay(page, "2020-02-17")
  await page.goBack()
  await expect
    .poll(() =>
      page.evaluate(
        () => document.getElementById("map-shell") !== window.__a6OldRoot,
      ),
    )
    .toBe(true)
  expect(await page.evaluate(() => window.__a6DocumentMarker)).toBe(
    "same-document-history",
  )
  await waitForMapLibre(page)
  expect(await page.evaluate(() => window.__a6Disconnected)).toEqual({
    "maps--maplibre": 1,
    "poster-studio-editor": 1,
    "video-studio": 1,
  })
  expect(await page.evaluate(() => window.__a6OldApp.controllers.length)).toBe(
    0,
  )
  for (const id of ["poster-studio", "video-studio"])
    await expect(page.locator(`#${id}`)).toHaveCount(1)
  await page.goForward()
  await waitForMapLibre(page)
  expect(await page.evaluate(() => window.__a6Disconnected)).toEqual({
    "maps--maplibre": 1,
    "poster-studio-editor": 1,
    "video-studio": 1,
  })
})

test("a controller import finishing after unmount cannot reconnect its disposed application", async ({
  page,
}) => {
  let release
  let heldResolve
  const held = new Promise((resolve) => {
    heldResolve = resolve
  })
  const released = new Promise((resolve) => {
    release = resolve
  })
  await page.route(
    /\/video_studio_controller[^/]*\.js(?:\?|$)/,
    async (route) => {
      heldResolve()
      await released
      await route.continue()
    },
  )
  try {
    await map(page)
    await held
    await page.evaluate(async () => {
      const shell = await import("map_shell")
      window.__a6DisposedApps = [...window.Stimulus.family]
      window.__a6LateRegistrations = 0
      for (const app of window.__a6DisposedApps) {
        const routerLoad = app.router.loadDefinition.bind(app.router)
        app.router.loadDefinition = (...args) => {
          window.__a6LateRegistrations++
          return routerLoad(...args)
        }
      }
      shell.unmount(document.getElementById("map-shell"))
    })
    release()
    await page.evaluate(async () => {
      await import("controllers/video_studio_controller")
    })
    expect(await page.evaluate(() => window.__a6LateRegistrations)).toBe(0)
    expect(
      await page.evaluate(() =>
        window.__a6DisposedApps.every((app) => app.controllers.length === 0),
      ),
    ).toBe(true)
  } finally {
    release()
  }
})

test("an interrupted shell import never mounts a detached hook root", async ({
  page,
}) => {
  let release
  let heldResolve
  const held = new Promise((resolve) => {
    heldResolve = resolve
  })
  const released = new Promise((resolve) => {
    release = resolve
  })
  await page.route(/\/phoenix\/js\/map_shell\.js(?:\?|$)/, async (route) => {
    heldResolve()
    await released
    await route.continue()
  })
  try {
    await page.goto("/map/v2")
    expect(new URL(page.url()).pathname).toBe("/map/v2")
    await held
    await page.evaluate(() => {
      window.__a6DetachedRoot = document.getElementById("map-shell")
      window.__a6DetachedRoot.remove()
      let current = window.Stimulus
      window.__a6DetachedMounts = 0
      Object.defineProperty(window, "Stimulus", {
        configurable: true,
        get: () => current,
        set(value) {
          current = value
          if (value.element === window.__a6DetachedRoot)
            window.__a6DetachedMounts++
        },
      })
    })
    release()
    await page.evaluate(async () => {
      await import("map_shell")
    })
    expect(await page.evaluate(() => window.__a6DetachedMounts)).toBe(0)
  } finally {
    release()
  }
})
