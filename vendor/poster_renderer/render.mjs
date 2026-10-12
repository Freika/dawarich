// Server-side poster renderer. Reads a job JSON (path as argv[2]), renders
// the map with maplibre-native using the app's own style modules, draws the
// same typography overlay the studio uses, and writes PNG (+ optional PDF).
//
// Run: node --import ./register.mjs render.mjs job.json
// (register.mjs resolves the app's importmap-style bare specifiers)
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import mbgl from "@maplibre/maplibre-gl-native"
import { createCanvas, registerFont } from "canvas"
import { resolveTheme } from "poster_studio/data/theme_loader"
import { encodePdf } from "poster_studio/export/pdf_encoder"
import { encodePng } from "poster_studio/export/png_encoder"
import { drawOverlay } from "poster_studio/render/overlay"
import { buildPosterStyle } from "poster_studio/render/style_builder"
import { formatCoords } from "poster_studio/render/text_layout"

const FONTS_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), "fonts")
const KNOWN_FONTS = ["inter", "oswald", "playfair-display", "jetbrains-mono"]
// Same visible-height semantics as the sidecar frame: ±distance/3 vertically.
const METERS_PER_LOGICAL_PX_AT_Z0 = 40075016.686 / 512

function zoomFor(lat, distance, logicalHeight) {
  const verticalSpanMeters = (2 * distance) / 3
  const metersPerPixel = verticalSpanMeters / logicalHeight
  const cosLat = Math.max(Math.cos((lat * Math.PI) / 180), 0.01)
  return Math.log2((METERS_PER_LOGICAL_PX_AT_Z0 * cosLat) / metersPerPixel)
}

function registerPosterFont(key) {
  const font = KNOWN_FONTS.includes(key) ? key : "oswald"
  for (const weight of ["400", "700"]) {
    registerFont(path.join(FONTS_DIR, `${font}-${weight}.ttf`), {
      family: "PosterFont",
      weight,
    })
  }
  return '"PosterFont", sans-serif'
}

function renderMap(style, view, size) {
  const map = new mbgl.Map({
    request: (req, cb) => {
      fetch(req.url)
        .then(async (res) => {
          if (res.status === 204 || res.status === 404) return cb(null, {})
          if (!res.ok) return cb(new Error(`HTTP ${res.status} ${req.url}`))
          cb(null, { data: Buffer.from(await res.arrayBuffer()) })
        })
        .catch(cb)
    },
    ratio: size.ratio,
  })
  map.load(style)
  return new Promise((resolve, reject) => {
    map.render(
      {
        center: [view.lon, view.lat],
        zoom: zoomFor(view.lat, view.distance, size.height),
        width: size.width,
        height: size.height,
      },
      (error, pixels) => {
        map.release()
        if (error) reject(error)
        else resolve(pixels)
      },
    )
  })
}

async function main() {
  const started = Date.now()
  const job = JSON.parse(fs.readFileSync(process.argv[2], "utf8"))
  const { view, size, text = {}, output } = job

  const theme = resolveTheme(job.tokens)
  const fontFamily = registerPosterFont(job.fontKey)
  const style = buildPosterStyle({
    theme,
    trackGeojson: job.trackGeojson ?? { type: "FeatureCollection", features: [] },
    trackOpacity: job.trackOpacity ?? 1,
    trackWidth: job.trackWidth ?? 1,
    ...(job.tilesUrl ? { tileUrl: job.tilesUrl } : {}),
  })

  const pixels = await renderMap(style, view, size)

  const pixelWidth = Math.round(size.width * size.ratio)
  const pixelHeight = Math.round(size.height * size.ratio)
  const canvas = createCanvas(pixelWidth, pixelHeight)
  const ctx = canvas.getContext("2d")
  const image = ctx.createImageData(pixelWidth, pixelHeight)
  image.data.set(pixels)
  ctx.putImageData(image, 0, 0)

  drawOverlay(canvas, {
    theme,
    title: text.title ?? "",
    subtitle: text.subtitle ?? "",
    coords: text.coords ? formatCoords({ lat: view.lat, lng: view.lon }) : "",
    font: fontFamily,
  })

  const rgba = ctx.getImageData(0, 0, pixelWidth, pixelHeight)
  fs.writeFileSync(
    output.png,
    encodePng(new Uint8Array(rgba.data.buffer), pixelWidth, pixelHeight, output.dpi ?? 0),
  )

  if (output.pdf) {
    // pdf_encoder expects the browser toBlob API; adapt node-canvas.
    canvas.toBlob = (cb, type, quality) =>
      cb(new Blob([canvas.toBuffer("image/jpeg", { quality: quality ?? 0.92 })]))
    const bytes = await encodePdf(canvas, {
      widthMm: output.widthMm,
      heightMm: output.heightMm,
    })
    fs.writeFileSync(output.pdf, bytes)
  }

  process.stdout.write(JSON.stringify({ ok: true, ms: Date.now() - started }))
  process.exit(0)
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`)
  process.exit(1)
})
