// Run via playwright-cli -s=photo3652 run-code --filename=spec/browser/photo_cluster_gallery.check.cjs
// biome-ignore lint/correctness/noUnusedVariables: playwright-cli invokes this function.
async function verifyPhotoClusterGallery(page) {
  const check = (value, message) => {
    if (!value) throw new Error(message)
  }
  const errors = []
  page.on("pageerror", (error) => errors.push(error.message))
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto("http://127.0.0.1:8796")
  await page.evaluate(() => window.ready)
  await page.evaluate(() => {
    const source = map.getSource(layer.sourceId)
    window.originalLeaves = source.getClusterLeaves.bind(source)
    window.calls = []
    source.getClusterLeaves = (...args) => {
      calls.push(args)
      return originalLeaves(...args)
    }
  })
  const dialog = page.getByRole("dialog")
  const thumbnails = page.locator(".photo-cluster-gallery__thumbnail")
  const openByClick = async () => {
    await page.evaluate(() => map.resize())
    await page.waitForFunction(() => map.loaded())
    const point = await page.evaluate(() => {
      const p = map.project([13.4, 52.5])
      const r = map.getCanvas().getBoundingClientRect()
      return { x: r.left + p.x, y: r.top + p.y }
    })
    await page.mouse.click(point.x, point.y)
    await dialog.waitFor()
    await page.waitForFunction(
      () => !document.querySelector('[aria-busy="true"]'),
    )
  }
  const close = async () => {
    await page.keyboard.press("Escape")
    await dialog.waitFor({ state: "detached" })
  }
  const initialZoom = await page.evaluate(() => map.getZoom())
  await openByClick()
  check(
    (await thumbnails.count()) === 24,
    "Initial page must be bounded at 24 thumbnails",
  )
  check(
    await page.evaluate(
      () => calls.length === 1 && calls[0][1] === 24 && calls[0][2] === 0,
    ),
    "Promise API limit/offset mismatch",
  )
  check(
    (await page.evaluate(() => map.getZoom())) === initialZoom,
    "Cluster click must not change zoom",
  )
  await page.getByRole("button", { name: "Close", exact: true }).focus()
  await page.keyboard.press("Shift+Tab")
  check(
    await page.evaluate(
      () =>
        document.activeElement === document.body ||
        document.activeElement.closest("dialog") !== null,
    ),
    "Focus escaped the modal",
  )
  await page.screenshot({ path: "tmp/photo-cluster-evidence/desktop.png" })
  const hostile = page.getByRole("button", {
    name: "<img src=x onerror=alert(1)>.jpg",
    exact: true,
  })
  await hostile.click()
  check(
    (await dialog.locator("script").count()) === 0,
    "Metadata injected markup",
  )
  check(
    (await dialog.locator(".photo-popup img").count()) === 1,
    "Expected only the preview image",
  )
  await page.screenshot({ path: "tmp/photo-cluster-evidence/detail.png" })
  await page.getByRole("button", { name: "Back to thumbnails" }).click()
  check(
    await hostile.evaluate((el) => el === document.activeElement),
    "Back did not restore thumbnail focus",
  )
  const ids = new Set()
  for (let i = 0; i < 5; i++) {
    for (const label of await thumbnails.evaluateAll((elements) =>
      elements.map((el) => el.getAttribute("aria-label")),
    ))
      ids.add(label)
    check((await thumbnails.count()) <= 24, "Page appended unbounded DOM")
    if (i < 4) {
      await page.getByRole("button", { name: "Next", exact: true }).click()
      await page.waitForFunction(
        () => !document.querySelector('[aria-busy="true"]'),
      )
    }
  }
  check(ids.size === 101, "Pagination lost same-coordinate photos")
  check((await thumbnails.count()) === 5, "Last page should have five photos")
  check(
    await page.getByRole("button", { name: "Next", exact: true }).isDisabled(),
    "Last page Next must be disabled",
  )
  await close()
  check(
    await page.evaluate(() => document.activeElement === map.getCanvas()),
    "Escape did not restore map focus",
  )
  await page.keyboard.press("Enter")
  await dialog.waitFor()
  await page.waitForFunction(
    () => !document.querySelector('[aria-busy="true"]'),
  )
  check((await thumbnails.count()) === 24, "Keyboard reopen failed")
  await close()
  await page.getByRole("button", { name: "Dark theme" }).click()
  await page.setViewportSize({ width: 390, height: 844 })
  await openByClick()
  check(
    await dialog.evaluate((el) => {
      const r = el.getBoundingClientRect()
      return (
        r.left >= 0 &&
        r.right <= innerWidth &&
        r.top >= 0 &&
        r.bottom <= innerHeight
      )
    }),
    "Mobile dialog overflows viewport",
  )
  check(
    await page
      .getByRole("button", { name: "Next", exact: true })
      .evaluate((el) => {
        const r = el.getBoundingClientRect()
        return r.top >= 0 && r.bottom <= innerHeight
      }),
    "Pagination out of viewport",
  )
  check(
    await dialog.evaluate(
      (el) => getComputedStyle(el).backgroundColor === "rgb(31, 41, 55)",
    ),
    "Actual Dawarich dark theme must style the gallery",
  )
  await page.screenshot({ path: "tmp/photo-cluster-evidence/mobile-dark.png" })
  await thumbnails.first().click()
  await page.screenshot({
    path: "tmp/photo-cluster-evidence/mobile-detail.png",
  })
  await close()
  await page.evaluate(() => map.jumpTo({ center: [13.4, 52.5], zoom: 22 }))
  await page.waitForFunction(() => map.loaded())
  await openByClick()
  check(
    (await thumbnails.count()) === 24,
    "Identical coordinates lost their cluster at maximum zoom",
  )
  await close()
  await page.evaluate(() => {
    map.getSource(layer.sourceId).getClusterLeaves = () =>
      new Promise((resolve) => {
        window.finishOldRequest = resolve
      })
    map.getCanvas().focus()
  })
  await page.keyboard.press("Enter")
  await page.getByText("Loading photos…", { exact: true }).waitFor()
  await page.evaluate(() => layer.update(data))
  await dialog.waitFor({ state: "detached" })
  await page.evaluate(() => finishOldRequest(features.slice(0, 24)))
  check((await dialog.count()) === 0, "Late response reopened a closed gallery")
  await page.evaluate(() => {
    map.getSource(layer.sourceId).getClusterLeaves = () =>
      Promise.reject(new Error("synthetic"))
    map.getCanvas().focus()
  })
  await page.keyboard.press("Enter")
  await page.getByRole("button", { name: "Retry", exact: true }).waitFor()
  await page.evaluate(() => {
    map.getSource(layer.sourceId).getClusterLeaves = window.originalLeaves
  })
  await page.getByRole("button", { name: "Retry", exact: true }).click()
  await page.waitForFunction(
    () =>
      document.querySelectorAll(".photo-cluster-gallery__thumbnail").length ===
      24,
  )
  await page.evaluate(() => layer.hide())
  await dialog.waitFor({ state: "detached" })
  await page.evaluate(() => {
    layer.show()
    map.getSource(layer.sourceId).getClusterLeaves = async () => []
    map.getCanvas().focus()
  })
  await page.keyboard.press("Enter")
  await page.getByText("No photos in this cluster.", { exact: true }).waitFor()
  await close()
  await page.evaluate(() => {
    map.getSource(layer.sourceId).getClusterLeaves = window.originalLeaves
    map.getCanvas().focus()
  })
  await page.keyboard.press("Enter")
  await dialog.waitFor()
  await page.evaluate(() => document.querySelector("#style").click())
  await dialog.waitFor({ state: "detached" })
  await page.waitForFunction(
    () => map.isStyleLoaded() && map.getSource("photos-source")?.loaded(),
  )
  await page.evaluate(() => map.jumpTo({ center: [13.4, 52.5], zoom: 12 }))
  await page.waitForFunction(() => map.loaded())
  await openByClick()
  check(
    (await thumbnails.count()) === 24,
    "Style rebuild failed to restore gallery",
  )
  await close()
  check(
    (await page.locator(".photo-marker").count()) === 1,
    "Single photo marker changed",
  )
  await page.locator(".photo-marker").click()
  await page.locator(".maplibregl-popup .photo-popup").waitFor()
  check(
    await page
      .locator(".maplibregl-popup")
      .innerText()
      .then((text) => text.includes("Single photo.jpg")),
    "Single photo popup failed",
  )
  check(errors.length === 0, `Browser errors: ${errors.join("; ")}`)
  return "PASS: real MapLibre click/Promise pagination, all 101 identical-coordinate photos, detail/back, Escape/Enter/focus, desktop/mobile/dark, max zoom, stale response, retry/empty, hide, style rebuild, single marker; no page errors."
}
