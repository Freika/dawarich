import { createHash } from 'node:crypto'
import { expect, test } from '@playwright/test'

const pageStates = new WeakMap()

function observePage(page) {
  if (pageStates.has(page)) return pageStates.get(page)
  const state = { documentResponse: null, assets: new Set() }
  const origin = new URL(process.env.NATIVE_IMPORTS_BASE_URL).origin
  page.on('response', response => {
    const request = response.request()
    if (request.isNavigationRequest() && request.frame() === page.mainFrame()
      && request.method() === 'GET' && response.status() === 200
      && response.headers()['content-type']?.startsWith('text/html')) state.documentResponse = response
  })
  page.on('request', request => {
    const url = new URL(request.url())
    if (url.origin === origin && url.pathname.startsWith('/assets/')) state.assets.add(request)
  })
  page.on('requestfinished', request => state.assets.delete(request))
  page.on('requestfailed', request => state.assets.delete(request))
  pageStates.set(page, state)
  return state
}

async function readyPage(page) {
  await page.waitForLoadState('load')
  await page.waitForFunction(async () => {
    const main = document.querySelector('[data-phx-main]')
    const root = main && window.liveSocket?.getRootById(main.id)
    const hosts = main ? [...document.querySelectorAll('[phx-hook="RailsStimulus"]')]
      : [document.querySelector('#achievement-unlocks')].filter(Boolean)
    for (const host of hosts) {
      const hook = root?.getHook(host)
      const application = main ? await hook?.bridge?.ready : window.Stimulus
      if (!application) return false
      for (const element of [host, ...host.querySelectorAll('[data-controller]')]) {
        for (const name of (element.getAttribute('data-controller') || '').split(/\s+/).filter(Boolean)) {
          const controller = application.getControllerForElementAndIdentifier(element, name)
          if (!controller) return false
          if (name === 'achievement-unlocks' && (controller.loading || controller.stopped)) return false
        }
      }
    }
    return hosts.length > 0
  }, null, { timeout: 15000 })
  await expect.poll(() => observePage(page).assets.size, { timeout: 15000, message: 'page asset requests complete' }).toBe(0)
}

export function fixture(kind) {
  const token = `${Date.now()}-${Math.random().toString(16).slice(2, 8)}`
  // Three non-anomalous points, with distinct timestamps across test executions.
  const start = 1709251200 + Math.floor(Date.now() / 1000) % 16000000
  const times = [0, 60, 120].map(offset => new Date((start + offset) * 1000).toISOString())
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="native-imports-acceptance" xmlns="http://www.topografix.com/GPX/1/1">
<trk><name>Rhéin native acceptance</name><trkseg>${times.map((time, n) =>
    `<trkpt lat="50.000${n}" lon="8.000${n}"><ele>120</ele><time>${time}</time></trkpt>`).join('')}
</trkseg></trk></gpx>`
  return { name: `native-${kind}-${token}.gpx`, mimeType: 'application/gpx+xml', buffer: Buffer.from(xml), times }
}

export async function registerAndSignIn(page, prefix) {
  observePage(page)
  const email = `e2e-native-${prefix}-${Date.now()}-${Math.random().toString(16).slice(2, 8)}@dawarich.test`
  const password = 'native-acceptance-password-12'
  const response = await page.request.post('/api/v1/auth/register', {
    data: { email, password, password_confirmation: password },
  })
  expect(response.ok(), `actual registration returned ${response.status()}`).toBeTruthy()
  await page.goto('/users/sign_in')
  await page.getByLabel('Email', { exact: true }).fill(email)
  await page.getByLabel('Password', { exact: true }).fill(password)
  await page.getByRole('button', { name: 'Log in', exact: true }).click()
  await expect(page).toHaveURL(/\/map/)
  await readyPage(page)
  return email
}

export async function nativePage(page, path) {
  const state = observePage(page)
  const current = state.documentResponse
  const reuse = new URL(page.url()).pathname === path && current && new URL(current.url()).pathname === path
  if (!reuse && await page.locator('[data-phx-main]').count()) {
    await expect(page.locator('[data-phx-main].phx-connected')).toBeVisible()
    await readyPage(page)
  }
  const response = reuse ? current : await page.goto(path)
  expect(response?.ok(), `native ${path} returned ${response?.status()}`).toBeTruthy()
  await expect(page.locator('[data-phx-main]')).toBeVisible()
  await expect(page.locator('[data-phx-main].phx-connected')).toBeVisible()
  if (path.startsWith('/imports')) {
    expect(response.status()).toBe(200)
    expect(response.headers()['x-dawarich-handler']).toBe('phoenix-imports')
    await expect(page.getByTestId('native-imports-root')).toBeVisible()
  }
  const dialog = page.locator('dialog#getting_started')
  const dialogState = await dialog.count() ? await dialog.evaluate(element => {
    const style = getComputedStyle(element)
    const bounds = element.getBoundingClientRect()
    return { open: element.open, openAttribute: element.hasAttribute('open'),
      display: style.display, visibility: style.visibility, opacity: style.opacity,
      width: bounds.width, height: bounds.height }
  }) : { absent: true }
  await test.info().attach('welcome-dialog-bounded-state', {
    body: JSON.stringify({ path, ...dialogState }), contentType: 'application/json',
  })
  const consent = page.getByRole('button', { name: 'No thanks', exact: true })
  if (await consent.isVisible()) {
    await test.info().attach('changelog-consent-bounded-state', {
      body: JSON.stringify(await consent.evaluate(element => ({
        tag: element.tagName, text: element.textContent.trim(), disabled: element.disabled,
        display: getComputedStyle(element).display, visibility: getComputedStyle(element).visibility,
      }))), contentType: 'application/json',
    })
    const before = test.info().outputPath('changelog-consent-visible.png')
    await page.screenshot({ path: before, fullPage: true })
    await test.info().attach('changelog-consent-visible', { path: before, contentType: 'image/png' })
    await consent.click()
    await expect(consent).toBeHidden()
    const after = test.info().outputPath('changelog-consent-dismissed.png')
    await page.screenshot({ path: after, fullPage: true })
    await test.info().attach('changelog-consent-dismissed', { path: after, contentType: 'image/png' })
  }
  // DaisyUI gives a closed dialog dimensions despite opacity: 0. Only an actually
  // open welcome dialog has a usable Skip button; keep the ordinary click path.
  const welcome = page.locator('dialog#getting_started[open]').filter({ has: page.getByRole('heading', { name: 'Welcome to Dawarich!', exact: true }) })
  if (await welcome.isVisible()) await welcome.getByRole('button', { name: 'Skip for now', exact: true }).click()
  await readyPage(page)
  return response
}

export async function settings(page, locale, zone) {
  await nativePage(page, '/settings/general')
  await page.locator('#timezone').selectOption(zone)
  await page.locator(`#locale_${locale}`).check({ force: true })
  await page.locator('form[action="/settings/general"] [type="submit"]').click()
  await nativePage(page, '/imports')
  await expect(page.locator('html')).toHaveAttribute('lang', locale)
}

export function row(page, name) {
  return page.locator('#imports tbody tr').filter({ has: page.getByRole('link', { name, exact: true }) })
}

// Raw GPX exercises real storage+native producer. Ordinary file selection wraps GPX client-side.
export async function createPlainImport(page, input) {
  await nativePage(page, '/imports/new')
  const csrf = await page.locator('meta[name="csrf-token"]').getAttribute('content')
  const upload = await page.request.post('/imports/direct_uploads', {
    headers: { 'X-CSRF-Token': csrf },
    data: { blob: { filename: input.name, content_type: input.mimeType,
      byte_size: input.buffer.length, checksum: createHash('md5').update(input.buffer).digest('base64') } },
  })
  expect(upload.ok(), `direct storage registration returned ${upload.status()}`).toBeTruthy()
  expect(upload.headers()['x-dawarich-handler']).toBe('phoenix-imports')
  const blob = await upload.json()
  const stored = await page.request.put(blob.direct_upload.url, {
    headers: blob.direct_upload.headers, data: input.buffer,
  })
  expect(stored.ok()).toBeTruthy()
  const created = await page.request.post('/imports', {
    form: { authenticity_token: csrf, 'import[files][]': blob.signed_id },
    maxRedirects: 0,
  })
  expect(created.status()).toBe(303)
  expect(created.headers()['x-dawarich-handler']).toBe('phoenix-imports')
  await nativePage(page, '/imports')
}

export async function createClientZipImport(page, input, evidence) {
  await nativePage(page, '/imports/new')
  const file = page.getByTestId('import-file-input')
  await expect(file).toBeVisible()
  await page.waitForFunction(async () => {
    const form = document.querySelector('[data-testid="import-file-input"]')?.closest('form')
    const main = form?.closest('[data-phx-main]')
    const hook = main && window.liveSocket?.getRootById(main.id)?.getHook(form)
    const application = await hook?.bridge?.ready
    return !!application?.getControllerForElementAndIdentifier(form, 'upload')
  })
  await file.setInputFiles({ name: input.name, mimeType: input.mimeType, buffer: input.buffer })
  const form = page.locator('form').filter({ has: file })
  await expect(page.getByTestId('import-upload-progress')).toBeVisible()
  await expect(form.getByText('100%', { exact: true })).toBeVisible({ timeout: 30000 })
  const descriptor = await form.locator('input[type="hidden"][name="import[files][]"]').inputValue()
  expect(JSON.parse(descriptor)).toMatchObject({ original_filename: input.name, client_wrapped: true })
  if (evidence) await evidence.screenshot(page, 'native-client-zip-upload-100-percent')
  const createdResponse = page.waitForResponse(response =>
    new URL(response.url()).pathname === '/imports' && response.request().method() === 'POST')
  await page.getByTestId('import-submit').click()
  const created = await createdResponse
  expect(created.status()).toBe(303)
  expect(created.headers()['x-dawarich-handler']).toBe('phoenix-imports')
  await expect(page).toHaveURL(/\/imports$/)
  await expect(page.locator('[data-phx-main].phx-connected')).toBeVisible()
}
