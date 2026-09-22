// Spectral Cartogram v15. Material math ported from the standalone playground.
// Two shared scans; geometry and identity are supplied by Rails, never per-card images.
const PALETTES = {
  common: {
    colors: ["#67707a", "#dce1e6", "#8f98a2", "#eef1f3"],
    accent: "#cbd2d8",
  },
  rare: {
    colors: ["#086cff", "#19d4c4", "#20a9e6", "#6ee7d2"],
    accent: "#2dbcf0",
  },
  epic: {
    colors: ["#7038ff", "#dd49ff", "#5d7cff", "#50d6ff"],
    accent: "#b667ff",
  },
  legendary: {
    colors: [
      "#07285d",
      "#075796",
      "#009ba9",
      "#073e52",
      "#36555a",
      "#d39735",
      "#bd6318",
    ],
    accent: "#efb348",
  },
}

const REFERENCE_PRESET = {
  scope: "country",
  geography: "brazil",
  rarity: "legendary",
  title: "Brazil Explorer",
  description: "Record memories across Brazil.",
  metricValue: "10",
  metricLabel: "places visited",
  subdivisions: false,
  foilIntensity: 100,
  foilBrightness: 102,
  foilContrast: 118,
  foilSaturation: 112,
  cardTexture: 85,
  paperLightAngle: 221,
  paperResolution: 180,
  paperDepth: 55,
  paperSource: "reference",
  foilRelighting: false,
  texture: 90,
  foilGrain: 92,
  foilRelief: 80,
  angle: 8,
  finish: "hammered",
  foilQuality: "reference",
  surfaceTexture: true,
  foilEdge: true,
  foilEdgeColor: "#db9a1b",
  foilEdgeWidth: 0.8,
  showJourney: false,
  showJourneyPins: true,
  showCompletionBadge: true,
  routeWidth: 4.4,
  markerScale: 82,
  mapScale: 115,
  mapStretch: 100,
  mapY: 0,
  copyY: 0,
  titleScale: 105,
  cardLight: true,
  lightIntensity: 45,
  lightAngle: 191,
  lightSoftness: 62,
  castShadow: true,
  shadowStrength: 91,
  animateFoil: true,
  colorShift: 20,
  showTierChip: false,
  tilt: 10,
  radius: 28,
  surface: "velvet",
  date: "20 Jul 2026",
}

const escapeHTML = (value) =>
  String(value).replace(
    /[&<>'"]/g,
    (char) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[
        char
      ],
  )

function hexToRgb(hex) {
  const n = parseInt(hex.slice(1), 16)
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255]
}

function mixHex(a, b, amount) {
  const aa = hexToRgb(a),
    bb = hexToRgb(b)
  const mixed = aa.map((v, i) => Math.round(v + (bb[i] - v) * amount))
  return "#" + mixed.map((v) => v.toString(16).padStart(2, "0")).join("")
}

function paletteFor(config) {
  const base = PALETTES[config.rarity]
  const intensity = Number(config.foilIntensity) / 100
  return {
    colors: base.colors.map((color) => mixHex("#252a2f", color, intensity)),
    accent: mixHex("#8c949b", base.accent, Math.max(0.35, intensity)),
  }
}

function texturePattern(id, finish, opacity) {
  if (finish === "satin" || finish === "hammered" || opacity <= 0) return ""
  if (finish === "micrograin") {
    return `<pattern id="${id}" width="7" height="7" patternUnits="userSpaceOnUse"><circle cx="1.2" cy="1.2" r=".65" fill="#fff" opacity="${opacity}"/><circle cx="5" cy="4" r=".45" fill="#000" opacity="${opacity * 0.8}"/></pattern>`
  }
  return `<pattern id="${id}" width="8" height="8" patternUnits="userSpaceOnUse" patternTransform="rotate(-12)"><path d="M0 1 H8 M0 5 H8" stroke="#fff" stroke-width=".45" opacity="${opacity}"/><path d="M0 3 H8 M0 7 H8" stroke="#000" stroke-width=".35" opacity="${opacity * 0.65}"/></pattern>`
}

function seedFor(value) {
  return [...String(value)].reduce(
    (seed, char) => (seed * 31 + char.charCodeAt(0)) % 997,
    17,
  )
}

function materialLightingFilter(id, depth, direction, paper = false) {
  const elevation = paper ? 28 : 38
  const azimuth = (Number(direction) + 90) % 360
  const gain = paper ? 3 : 2.5
  const intercept = 0.5 - gain * Math.sin((elevation * Math.PI) / 180)
  const lightTag = paper ? "" : "data-foil-light"
  return `<filter id="${id}" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB">
    <feColorMatrix in="SourceGraphic" type="luminanceToAlpha" result="height"/>
    <feDiffuseLighting in="height" surfaceScale="${((Number(depth) / 100) * (paper ? 1.8 : 1.3)).toFixed(2)}" diffuseConstant="1" lighting-color="#ffffff" result="diffuse"><feDistantLight ${lightTag} azimuth="${azimuth}" elevation="${elevation}"/></feDiffuseLighting>
    <feComponentTransfer in="diffuse" result="relief"><feFuncR type="linear" slope="${gain}" intercept="${intercept}"/><feFuncG type="linear" slope="${gain}" intercept="${intercept}"/><feFuncB type="linear" slope="${gain}" intercept="${intercept}"/></feComponentTransfer>
    ${paper ? "" : `<feSpecularLighting in="height" surfaceScale="${(Number(depth) / 100) * 1.3}" specularConstant=".7" specularExponent="18" lighting-color="#ffffff" result="facets"><feDistantLight data-foil-light azimuth="${azimuth}" elevation="${elevation}"/></feSpecularLighting><feComposite in="relief" in2="facets" operator="arithmetic" k2="1" k3=".45"/>`}
  </filter>`
}

function paperMarkup(config, uid) {
  if (!config.surfaceTexture) return ""
  if (config.paperSource === "cotton")
    return `<div class="material-texture" aria-hidden="true" style="--material-opacity:${(Number(config.cardTexture) / 100) * 0.5}"></div>`
  const size = 630 + (200 - Number(config.paperResolution)) * 2
  const seed = seedFor(config.geography)
  const x = -(size - 400) * ((seed % 61) / 60),
    y = -(size - 600) * ((seed % 43) / 42)
  if (config.paperSource === "reference") {
    // Preserve photographed fibers. A restrained directional kernel adjusts their
    // edge contrast; don't reinterpret the scan as a deeply embossed height map.
    const depth = Number(config.paperDepth) / 100
    const angle = (Number(config.paperLightAngle) * Math.PI) / 180
    const dx = Math.sin(angle) * depth * 0.35,
      dy = -Math.cos(angle) * depth * 0.35
    const gain = 0.12 + depth * 0.3
    const bias = 0.048 - gain * 0.5
    return `<svg class="paper-surface paper-reference" viewBox="0 0 400 600" preserveAspectRatio="none" aria-hidden="true" style="opacity:${Number(config.cardTexture) / 100}"><defs><filter id="paper-light-${uid}" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB"><feConvolveMatrix order="3" kernelMatrix="0 ${-dy} 0 ${-dx} 1 ${dx} 0 ${dy} 0" divisor="1" edgeMode="duplicate" preserveAlpha="true"/><feComponentTransfer>${["R", "G", "B"].map((c) => `<feFunc${c} type="linear" slope="${gain}" intercept="${bias}"/>`).join("")}</feComponentTransfer></filter></defs><image href="${escapeHTML(config.paperAsset)}" x="${x}" y="${y}" width="${size}" height="${size}" filter="url(#paper-light-${uid})"/></svg>`
  }
  return `<svg class="paper-surface" viewBox="0 0 400 600" preserveAspectRatio="none" aria-hidden="true" style="opacity:${Number(config.cardTexture) / 100}"><defs>${materialLightingFilter(`paper-light-${uid}`, config.paperDepth, config.paperLightAngle, true)}</defs><image href="assets/paper-fiber-height-4k.webp" x="${x}" y="${y}" width="${size}" height="${size}" filter="url(#paper-light-${uid})"/></svg>`
}

function mapSvg(config, uid) {
  const geo = config.geometry
  const palette = paletteFor(config)
  const colors = palette.colors
  const gradientId = `foil-${uid}`
  const edgeGradientId = `foil-edge-${uid}`
  const textureId = `texture-${uid}`
  const clipId = `shape-${uid}`
  const markerGradientId = `marker-gradient-${uid}`
  const warmEastId = `warm-east-${uid}`
  const coolSouthId = `cool-south-${uid}`
  const warmSouthId = `warm-south-${uid}`
  const metalShadeId = `metal-shade-${uid}`
  const metalCobaltId = `metal-cobalt-${uid}`
  const shapeId = `geography-${uid}`
  const reliefId = `foil-relief-${uid}`
  const edgeMaskId = `foil-edge-mask-${uid}`
  const legendaryOffsets = [0, 25, 43, 57, 69, 85, 100]
  const stops = colors
    .map(
      (color, i) =>
        `<stop offset="${config.rarity === "legendary" ? legendaryOffsets[i] : Math.round((i / Math.max(1, colors.length - 1)) * 100)}%" stop-color="${color}"/>`,
    )
    .join("")
  const edgeColor = config.foilEdgeColor || palette.accent
  const edgeStops = `<stop offset="0%" stop-color="${mixHex(edgeColor, "#fff6d4", 0.6)}" stop-opacity=".95"/><stop offset="30%" stop-color="${edgeColor}" stop-opacity=".22"/><stop offset="58%" stop-color="${mixHex(edgeColor, "#ffedb5", 0.4)}" stop-opacity=".8"/><stop offset="78%" stop-color="${edgeColor}" stop-opacity=".12"/><stop offset="100%" stop-color="${edgeColor}" stop-opacity=".55"/>`
  const fillPaths = `<use class="geo-fill" href="#${shapeId}" fill="url(#${gradientId})"/>`
  const accentPaths =
    config.rarity === "legendary"
      ? `<use class="geo-accent" href="#${shapeId}" fill="url(#${warmEastId})" opacity=".92"/><use class="geo-accent" href="#${shapeId}" fill="url(#${coolSouthId})" opacity=".62"/><use class="geo-accent" href="#${shapeId}" fill="url(#${warmSouthId})" opacity=".82"/>`
      : ""
  // Broad colored reflections create quiet petrol areas between fine bright
  // facets. They stay inside the metal and never add a white glare overlay.
  const metalShading =
    config.rarity === "legendary" && config.foilQuality === "reference"
      ? `<use class="geo-accent" href="#${shapeId}" fill="url(#${metalShadeId})"/><use class="geo-accent" href="#${shapeId}" fill="url(#${metalCobaltId})"/>`
      : ""
  const textureSeed = seedFor(config.geography)
  const scanSize = 520 - Number(config.foilGrain) * 2
  const scanX =
    (-((textureSeed * 17) % 101) / 100) * Math.max(0, scanSize - 300)
  const scanY =
    (-((textureSeed * 37) % 101) / 100) * Math.max(0, scanSize - 260)
  const textureStrength = Number(config.texture) / 100
  const reliefStrength = Number(config.foilRelief) / 100
  const metallicReliefBoost = config.foilQuality === "metallic" ? 1.15 : 1
  const metallicSparkleBoost = config.foilQuality === "metallic" ? 1.2 : 1
  const scanReliefOpacity =
    config.foilQuality === "reference"
      ? Math.min(1, (0.55 + reliefStrength * 0.5) * textureStrength)
      : Math.min(
          1,
          (0.18 + reliefStrength * 0.42) *
            textureStrength *
            metallicReliefBoost,
        )
  const scanSparkleOpacity =
    config.foilQuality === "reference"
      ? (0.012 + reliefStrength * 0.035) * textureStrength
      : Math.min(
          1,
          (0.025 + reliefStrength * 0.13) *
            textureStrength *
            metallicSparkleBoost,
        )
  const foilScanAsset =
    config.foilQuality === "reference"
      ? escapeHTML(config.foilAsset)
      : config.foilQuality === "compact"
        ? "assets/foil-microrelief-v1.webp"
        : config.foilQuality === "studio"
          ? "assets/foil-microrelief-studio-v2.webp"
          : "assets/foil-metallic-membrane-v3.webp"
  let texturePaths =
    config.finish === "satin" || Number(config.texture) === 0
      ? ""
      : config.finish === "hammered"
        ? `<g class="geo-scan-relief-layer ${config.foilQuality}" clip-path="url(#${clipId})" opacity="${scanReliefOpacity.toFixed(3)}"><image class="geo-scan-relief ${config.foilQuality}" href="${foilScanAsset}" x="${scanX.toFixed(1)}" y="${scanY.toFixed(1)}" width="${scanSize.toFixed(1)}" height="${scanSize.toFixed(1)}" preserveAspectRatio="none"/></g><g class="geo-scan-sparkle-layer ${config.foilQuality}" clip-path="url(#${clipId})" opacity="${scanSparkleOpacity.toFixed(3)}"><image class="geo-scan-sparkle ${config.foilQuality}" href="${foilScanAsset}" x="${scanX.toFixed(1)}" y="${scanY.toFixed(1)}" width="${scanSize.toFixed(1)}" height="${scanSize.toFixed(1)}" preserveAspectRatio="none"/></g>`
        : `<use class="geo-texture" href="#${shapeId}" fill="url(#${textureId})" opacity="${Number(config.texture) / 100}"/>`
  if (
    config.finish === "hammered" &&
    config.foilRelighting &&
    Number(config.texture) > 0
  ) {
    texturePaths = `<g class="geo-relit" clip-path="url(#${clipId})" opacity="${Math.min(1, textureStrength * 1.25)}"><image href="${foilScanAsset}" x="${scanX}" y="${scanY}" width="${scanSize}" height="${scanSize}" filter="url(#${reliefId})"/></g>`
  }
  const edgePrismPaths = config.foilEdge
    ? `<use class="geo-edge-prism" href="#${shapeId}" stroke="url(#${edgeGradientId})" stroke-width="${Number(config.foilEdgeWidth)}" mask="url(#${edgeMaskId})"/>`
    : ""
  const boundaries = config.subdivisions
    ? `<g clip-path="url(#${clipId})">${geo.boundaries.map((d) => `<path class="boundary" d="${d}"/>`).join("")}</g>`
    : ""
  const textureDef = texturePattern(textureId, config.finish, 0.32)
  const journey = "" // No decorative routes or fictional location pins.

  return `<svg viewBox="0 0 300 260" role="img" aria-label="${escapeHTML(geo.label)} cartogram">
    <defs>
      <path id="${shapeId}" d="${geo.fills.map(escapeHTML).join("")}" fill-rule="evenodd"/>
      ${config.finish === "hammered" && config.foilRelighting ? materialLightingFilter(reliefId, config.foilRelief, config.lightAngle) : ""}
      <filter id="edge-grain-${uid}" color-interpolation-filters="sRGB"><feTurbulence type="fractalNoise" baseFrequency=".14" numOctaves="1" seed="${textureSeed}"/><feColorMatrix values="0 0 0 0 1 0 0 0 0 1 0 0 0 0 1 0 0 0 3 -.8"/></filter>
      <mask id="${edgeMaskId}" maskUnits="userSpaceOnUse" x="0" y="0" width="300" height="260"><rect width="300" height="260" fill="white" filter="url(#edge-grain-${uid})"/></mask>
      <linearGradient id="${gradientId}" data-spectrum x1="-20" y1="40" x2="320" y2="220" gradientUnits="userSpaceOnUse" gradientTransform="rotate(${config.angle} 150 130)">${stops}</linearGradient>
      <linearGradient id="${edgeGradientId}" data-spectrum x1="-20" y1="40" x2="320" y2="220" gradientUnits="userSpaceOnUse" gradientTransform="rotate(${config.angle} 150 130)">${edgeStops}</linearGradient>
      <radialGradient id="${warmEastId}" cx="250" cy="90" r="97" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#ffe29b"/><stop offset="24%" stop-color="#eab354" stop-opacity=".98"/><stop offset="64%" stop-color="#9c6231" stop-opacity=".5"/><stop offset="100%" stop-color="#725445" stop-opacity="0"/></radialGradient>
      <radialGradient id="${coolSouthId}" cx="175" cy="181" r="58" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#00dded"/><stop offset="34%" stop-color="#00b9cc" stop-opacity=".94"/><stop offset="78%" stop-color="#007e8d" stop-opacity="0"/></radialGradient>
      <radialGradient id="${warmSouthId}" cx="164" cy="230" r="38" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#ffd044"/><stop offset="46%" stop-color="#ef8b1b" stop-opacity=".92"/><stop offset="100%" stop-color="#d95a13" stop-opacity="0"/></radialGradient>
      <radialGradient id="${metalShadeId}" cx="120" cy="84" r="107" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#031e2e" stop-opacity=".78"/><stop offset="40%" stop-color="#032638" stop-opacity=".6"/><stop offset="100%" stop-color="#032638" stop-opacity="0"/></radialGradient>
      <radialGradient id="${metalCobaltId}" cx="32" cy="92" r="74" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#006fea" stop-opacity=".84"/><stop offset="38%" stop-color="#0050a3" stop-opacity=".46"/><stop offset="100%" stop-color="#0050a3" stop-opacity="0"/></radialGradient>
      <clipPath id="${clipId}"><use href="#${shapeId}"/></clipPath>
      ${textureDef}
      <radialGradient id="${markerGradientId}" cx="34%" cy="28%" r="72%"><stop offset="0" stop-color="#fff7dc"/><stop offset="28%" stop-color="#ffd46a"/><stop offset="66%" stop-color="#ff9e16"/><stop offset="100%" stop-color="#754000"/></radialGradient>
    </defs>
    <g><g class="geo-foil-composite">${fillPaths}${accentPaths}${metalShading}${texturePaths}</g>${edgePrismPaths}${boundaries}${journey}</g>
  </svg>`
}

export function spectralMarkup({
  silhouette,
  key,
  rarity,
  paperAsset,
  foilAsset,
  uid,
}) {
  const box = String(silhouette.viewbox).split(/\s+/).map(Number)
  if (
    box.length !== 4 ||
    !box.every(Number.isFinite) ||
    box[2] <= 0 ||
    box[3] <= 0
  )
    return ""
  const [x, y, width, height] = box
  // Equirectangular projection at the shape's middle latitude, preserving proportions.
  const longitudeScale = Math.max(
    0.2,
    Math.cos(((y + height / 2) * Math.PI) / 180),
  )
  const scale = Math.min(276 / (width * longitudeScale), 236 / height)
  // Normalize geometry, not its SVG transform: transforming the reference path
  // would also transform userSpaceOnUse gradients and flatten the spectrum.
  // PostGIS ST_AsSVG(..., 0) emits absolute polygon M/L/Z commands only.
  const path = String(silhouette.path)
  const tokenPattern = /[MLZ]|[-+]?(?:\d*\.?\d+)(?:[eE][-+]?\d+)?/g
  if (path.replace(tokenPattern, "").replace(/[\s,]/g, "")) return ""
  let coordinate = 0
  const normalized = (path.match(tokenPattern) || [])
    .map((token) => {
      if (/^[MLZ]$/.test(token)) return token
      const value = Number(token)
      return (
        coordinate++ % 2 === 0
          ? 150 + (value - x - width / 2) * scale * longitudeScale
          : 130 + (value - y - height / 2) * scale
      ).toFixed(4)
    })
    .join(" ")
  if (!coordinate || coordinate % 2 || normalized.includes("Infinity"))
    return ""
  const tier = Object.hasOwn(PALETTES, rarity.toLowerCase())
    ? rarity.toLowerCase()
    : "common"
  const config = {
    ...REFERENCE_PRESET,
    geography: key,
    rarity: tier,
    paperAsset,
    foilAsset,
    geometry: { label: key, fills: [normalized], boundaries: [] },
  }
  return {
    html:
      paperMarkup(config, uid) +
      '<div class="geo-stage">' +
      mapSvg(config, uid) +
      "</div>",
    accent: PALETTES[tier].accent,
  }
}
