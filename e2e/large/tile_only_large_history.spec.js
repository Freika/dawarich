import { readFile } from "node:fs/promises"
import { expect, test } from "@playwright/test"
import {
  blockOutboundAndStubBasemap,
  waitForMapController,
} from "../helpers.js"

test("million-point multi-year history initializes only through vector tiles", async ({
  page,
}) => {
  test.setTimeout(120_000)
  const seed = JSON.parse(await readFile("e2e/temp/seed.json", "utf8"))
  expect(seed.large_point_count).toBe(1_000_000)

  const requests = []
  const tileResponses = []
  page.on("request", (request) =>
    requests.push(new URL(request.url()).pathname),
  )
  page.on("response", (response) => {
    const path = new URL(response.url()).pathname
    if (path.startsWith("/api/v1/tiles/points/")) {
      tileResponses.push(response.status())
    }
  })
  await blockOutboundAndStubBasemap(page)

  const { start_at: startAt, end_at: endAt } = seed.large_history_scope
  await page.goto(
    `/map?start_at=${encodeURIComponent(startAt)}&end_at=${encodeURIComponent(endAt)}`,
  )
  await waitForMapController(page)
  await expect
    .poll(
      () => tileResponses.some((status) => [200, 204, 304].includes(status)),
      {
        timeout: 90_000,
      },
    )
    .toBe(true)

  expect(
    requests.some((path) => path.startsWith("/api/v1/tiles/points/")),
  ).toBe(true)
  expect(requests.some((path) => path === "/api/v1/points")).toBe(false)
  expect(requests.some((path) => path === "/api/v1/tracks")).toBe(false)
})
