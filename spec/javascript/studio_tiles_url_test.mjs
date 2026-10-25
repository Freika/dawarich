import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const toModuleUrl = (code) =>
  `data:text/javascript;base64,${Buffer.from(code).toString("base64")}`

const readApp = (path) =>
  readFile(new URL(`../../app/javascript/${path}`, import.meta.url), "utf8")

const stripImports = (source) =>
  source.replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")

const { studioTilesUrl } = await import(
  toModuleUrl(await readApp("maps_maplibre/utils/basemap_url.js"))
)
globalThis.__studioTilesUrl = studioTilesUrl

const stubs = `
class Controller {}
const translate = (key) => key
const buildPosterStyle = (options) => options
const resolveTheme = (tokens) => tokens
const DAWARICH_BLUE = "#2563EB"
const studioTilesUrl = globalThis.__studioTilesUrl
`

const { default: PosterStudioController } = await import(
  toModuleUrl(
    stubs +
      stripImports(
        await readApp("controllers/poster_studio_editor_controller.js"),
      ),
  )
)
const { buildVideoStyle, defaultSettings } = await import(
  toModuleUrl(
    stubs + stripImports(await readApp("video_studio/studio_state.js")),
  )
)

const VECTOR_URL = "https://tiles.example.test/planet/{z}/{x}/{y}.mvt"

test("studios use a custom vector tiles URL when fallback is off", () => {
  assert.equal(studioTilesUrl(VECTOR_URL, false), VECTOR_URL)
  assert.equal(studioTilesUrl(`  ${VECTOR_URL}  `, false), VECTOR_URL)
})

test("studios keep the default tiles for anything they cannot theme", () => {
  assert.equal(studioTilesUrl(VECTOR_URL, true), undefined)
  assert.equal(
    studioTilesUrl("https://tiles.example.test/{z}/{x}/{y}.png", false),
    undefined,
  )
  assert.equal(
    studioTilesUrl("https://tiles.example.test/style.json", false),
    undefined,
  )
  assert.equal(studioTilesUrl("", false), undefined)
  assert.equal(studioTilesUrl(null, false), undefined)
})

function posterController(tilesUrl, tilesFallback) {
  return Object.assign(new PosterStudioController(), {
    tokens: {},
    provider: { trackGeojson: () => null },
    hidden: new Set(),
    trackOpacityTarget: { value: "100" },
    trackWidthTarget: { value: "100" },
    tilesUrlValue: tilesUrl,
    tilesFallbackValue: tilesFallback,
  })
}

test("poster studio style reads the user's tiles URL", () => {
  assert.equal(
    posterController(VECTOR_URL, false).posterStyle().tileUrl,
    VECTOR_URL,
  )
  assert.equal(
    posterController(VECTOR_URL, true).posterStyle().tileUrl,
    undefined,
  )
  assert.equal(posterController("", false).posterStyle().tileUrl, undefined)
})

test("video studio style carries the tiles URL it is given", () => {
  const style = buildVideoStyle({
    tokens: {},
    trackGeojson: null,
    settings: defaultSettings(),
    tileUrl: VECTOR_URL,
  })

  assert.equal(style.tileUrl, VECTOR_URL)
})
