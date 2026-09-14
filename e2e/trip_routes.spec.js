import { readFile } from "node:fs/promises"
import { expect, test } from "@playwright/test"
import { blockOutboundAndStubBasemap } from "./helpers.js"

async function seedData() {
  return JSON.parse(await readFile("e2e/temp/seed.json", "utf8"))
}

test("Trip and shared-Trip keep their day routes after main-map cutover", async ({
  page,
}) => {
  const seed = await seedData()
  const requests = []
  page.on("request", (request) =>
    requests.push(new URL(request.url()).pathname),
  )
  await blockOutboundAndStubBasemap(page)

  await page.goto(`/trips/${seed.trip_id}`)
  await expect
    .poll(
      () =>
        page.evaluate(() => {
          const element = document.querySelector(
            '[data-controller~="trip-maplibre"]',
          )
          const controller =
            window.Stimulus?.getControllerForElementAndIdentifier(
              element,
              "trip-maplibre",
            )
          return {
            days: controller?.dayRoutesLayer?.getDayKeys().length || 0,
            layers:
              controller?.map
                ?.getStyle()
                ?.layers?.filter((layer) =>
                  layer.id.startsWith("day-route-layer-"),
                ).length || 0,
          }
        }),
      { timeout: 30_000 },
    )
    .toEqual({ days: 1, layers: 1 })
  expect(requests.some((path) => path === "/api/v1/points")).toBe(true)

  requests.length = 0
  await page.goto(`/s/${seed.shared_trip_id}`)
  await expect
    .poll(
      () =>
        page.evaluate(() => {
          const element = document.querySelector(
            '[data-controller~="shared-trip-map"]',
          )
          const controller =
            window.Stimulus?.getControllerForElementAndIdentifier(
              element,
              "shared-trip-map",
            )
          return {
            days: controller?.dayRoutesLayer?.getDayKeys().length || 0,
            layers:
              controller?.map
                ?.getStyle()
                ?.layers?.filter((layer) =>
                  layer.id.startsWith("day-route-layer-"),
                ).length || 0,
          }
        }),
      { timeout: 30_000 },
    )
    .toEqual({ days: 1, layers: 1 })
  expect(
    requests.some((path) =>
      path.startsWith(`/api/v1/shared/${seed.shared_trip_id}/points`),
    ),
  ).toBe(true)
})
