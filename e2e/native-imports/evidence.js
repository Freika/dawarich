import { expect, test as base } from '@playwright/test'

function safeURL(value) {
  try {
    const url = new URL(value)
    return `${url.origin}${url.pathname.replace(/(\/imports\/uploads\/)[^/]+/, '$1[redacted]')}`
  } catch { return '[non-URL]' }
}

function safeText(value) {
  return value.replace(/https?:\/\/[^\s"'<>]+/g, safeURL)
    .replace(/(bearer\s+|(?:token|password|secret|api[_-]?key)\s*[:=]\s*)[^\s,;]+/gi, '$1[redacted]')
    .replace(/[\w+/=-]{32,}--[\w+/=-]+/g, '[signed-value-redacted]')
    .slice(0, 5000)
}

export function isSetupNavigationCancellation(request) {
  let asset, from, to, sameOrigin
  try {
    const resource = new URL(request.url)
    const document = new URL(request.documentURL)
    const navigation = new URL(request.navigationURL)
    asset = resource.pathname
    from = document.pathname
    to = navigation.pathname
    sameOrigin = resource.origin === document.origin && document.origin === navigation.origin
  } catch { return false }
  const mapScripts = new Set([
    '/assets/maps_maplibre/components/toast', '/assets/maps_maplibre/layers/base_layer',
    '/assets/maps_maplibre/layers/fog_hexagon_source', '/assets/maps_maplibre/layers/heatmap_layer',
    '/assets/maps_maplibre/utils/family_member_color', '/assets/maps_maplibre/utils/flight_arcs',
    '/assets/maps_maplibre/utils/geojson_transformers', '/assets/maps_maplibre/utils/geometry',
    '/assets/maps_maplibre/utils/h3_resolution', '/assets/maps_maplibre/utils/marker_theme',
    '/assets/maps_maplibre/utils/progressive_loader', '/assets/maps_maplibre/utils/popup_theme',
    '/assets/poster_studio/data/protomaps_schema.js',
  ])
  const settingsAssets = {
    image: new Set(['/assets/Download_on_the_App_Store_Badge_US-UK_RGB_blk_092917.svg',
      '/assets/GetItOnGooglePlay_Badge_Web_color_English.svg', '/assets/logo.svg']),
    stylesheet: new Set(['/assets/achievements.css', '/assets/achievements_unlocks.css', '/assets/inter-font.css']),
  }
  const mapNavigation = ['/map', '/map/v2'].includes(from) && ['/settings/general', '/imports'].includes(to)
    && request.resourceType === 'script' && mapScripts.has(asset)
  const settingsNavigation = from === '/settings/general' && to === '/imports'
    && !!settingsAssets[request.resourceType]?.has(asset)
  return sameOrigin && request.role === 'owner' && request.phase === 'setup' && request.startedPhase === 'setup'
    && request.error === 'net::ERR_ABORTED' && request.method === 'GET' && (mapNavigation || settingsNavigation)
}

export function actorPhase(role, nativeStarted, phase) {
  return role === 'foreign' && !nativeStarted ? 'setup' : phase
}

export function isNativeImportsDocument(response, origin) {
  try {
    const url = new URL(response.url)
    return url.origin === origin && /^\/imports(?:\/|$)/.test(url.pathname)
      && response.mainFrameNavigation === true && response.method === 'GET' && response.status === 200
      && response.handler === 'phoenix-imports' && !!response.contentType?.startsWith('text/html')
  } catch { return false }
}

export function isCommittedNativeDocument(verifiedURL, documentURL, origin) {
  try {
    const verified = new URL(verifiedURL)
    const current = new URL(documentURL)
    return verified.origin === origin && current.origin === origin
      && /^\/imports(?:\/|$)/.test(current.pathname) && current.pathname === verified.pathname
  } catch { return false }
}

export const test = base.extend({
  evidence: async ({ page }, use, testInfo) => {
    const consoleMessages = []
    const pageErrors = []
    const failedRequests = []
    const httpErrors = []
    const websocketErrors = []
    const protocolResponses = []
    const listeners = []
    const downloads = new Set()
    const origin = new URL(process.env.NATIVE_IMPORTS_BASE_URL).origin
    let phase = 'setup'
    const nativeResource = url => {
      const parsed = new URL(url)
      return parsed.origin === origin && /^\/(imports(?:\/|$)|assets\/)/.test(parsed.pathname)
    }
    const watch = (observed, role) => {
      const started = new WeakMap()
      let navigationURL = observed.url()
      let nativeStarted = false
      let verifiedNativeURL
      const observedPhase = () => actorPhase(role, nativeStarted, phase)
      const commitNativePhase = () => {
        if (verifiedNativeURL && isCommittedNativeDocument(verifiedNativeURL, observed.url(), origin)) nativeStarted = true
      }
      const on = (event, callback) => {
        observed.on(event, callback)
        listeners.push(() => observed.off(event, callback))
      }
      on('console', message => consoleMessages.push({
        role, phase: observedPhase(), documentURL: safeURL(observed.url()), type: message.type(), text: safeText(message.text()),
        location: { ...message.location(), url: safeURL(message.location().url) },
      }))
      on('pageerror', error => pageErrors.push({ role, phase: observedPhase(), message: safeText(error.message) }))
      on('framenavigated', frame => { if (frame === observed.mainFrame()) commitNativePhase() })
      on('request', request => {
        started.set(request, { startedPhase: observedPhase(), documentURL: safeURL(observed.url()) })
        if (request.isNavigationRequest() && request.frame() === observed.mainFrame()) navigationURL = request.url()
      })
      on('requestfailed', request => {
        const entry = {
          role, phase: observedPhase(), url: safeURL(request.url()), method: request.method(),
          resourceType: request.resourceType(), error: request.failure()?.errorText,
          nativeResource: nativeResource(request.url()),
          ...started.get(request), navigationURL: safeURL(navigationURL),
        }
        // Missing request-start evidence cannot qualify for an expected cancellation.
        entry.setupNavigationCancellation = !!entry.documentURL && entry.documentURL !== '[non-URL]'
          && entry.navigationURL !== '[non-URL]' && isSetupNavigationCancellation(entry)
        failedRequests.push(entry)
      })
      on('response', response => {
        const request = response.request()
        if (isNativeImportsDocument({ url: response.url(), status: response.status(),
          method: request.method(), handler: response.headers()['x-dawarich-handler'],
          contentType: response.headers()['content-type'],
          mainFrameNavigation: request.isNavigationRequest() && request.frame() === observed.mainFrame() }, origin)) {
          verifiedNativeURL = response.url()
          commitNativePhase()
        }
        if (response.status() >= 400) httpErrors.push({
          role, phase: observedPhase(), url: safeURL(response.url()), status: response.status(),
          method: response.request().method(), nativeResource: nativeResource(response.url()),
        })
      })
      on('websocket', socket => {
        const failed = error => websocketErrors.push({ role, phase: observedPhase(), url: safeURL(socket.url()), error: safeText(String(error)) })
        socket.on('socketerror', failed)
        listeners.push(() => socket.off('socketerror', failed))
      })
    }
    watch(page, 'owner')
    const evidence = {
      watch,
      phase(value) { phase = value },
      downloaded(id) { downloads.add(`/imports/${id}/download`) },
      protocol(label, response) {
        protocolResponses.push({ label, url: safeURL(response.url()), status: response.status(),
          handler: response.headers()['x-dawarich-handler'] })
      },
      async screenshot(observed, label) {
        const path = testInfo.outputPath(`${label}.png`)
        await observed.screenshot({ path, fullPage: true })
        await testInfo.attach(label, { path, contentType: 'image/png' })
      },
    }
    try {
      await use(evidence)
      const unexpectedRequests = failedRequests.filter(request => {
        // Chromium aborts navigation when a successful download is handed to the browser.
        const expectedDownload = downloads.has(new URL(request.url).pathname)
          && request.error === 'net::ERR_ABORTED'
        return request.nativeResource && !expectedDownload && !request.setupNavigationCancellation
      })
      expect(pageErrors.filter(error => error.phase !== 'setup'), 'native workflow page errors').toEqual([])
      expect(consoleMessages.filter(message => message.phase !== 'setup' && message.type === 'error'), 'native workflow console errors').toEqual([])
      expect(httpErrors.filter(response => response.nativeResource), 'native browser HTTP failures').toEqual([])
      expect(unexpectedRequests, 'native browser transport failures').toEqual([])
      expect(websocketErrors.filter(socket => /^\/phoenix\/live(?:\/|$)/.test(new URL(socket.url).pathname)), 'LiveView websocket failures').toEqual([])
    } finally {
      for (const remove of listeners) remove()
      await testInfo.attach('browser-console-pageerror-network-evidence', {
        body: JSON.stringify({ consoleMessages, pageErrors, failedRequests, httpErrors, websocketErrors, protocolResponses,
          verifiedDownloadAbortPaths: [...downloads] }, null, 2),
        contentType: 'application/json',
      })
    }
  },
})

export { expect }
