// Display-only SVG paths; no D3, projection or geometry dependency at runtime.
// npm install --prefix tmp/achievement-globe-generator --no-save --ignore-scripts d3-geo@3.1.1
// node script/build_achievement_globes.mjs tmp/achievement-globe-land.geojson
import { readFileSync, writeFileSync } from "node:fs"
import { resolve } from "node:path"
import { pathToFileURL } from "node:url"
import { createHash } from "node:crypto"
const packageRoot = resolve(
  "tmp/achievement-globe-generator/node_modules/d3-geo",
)
const version = JSON.parse(
  readFileSync(packageRoot + "/package.json", "utf8"),
).version
if (version !== "3.1.1") throw new Error("Use pinned d3-geo@3.1.1")
const { geoOrthographic, geoPath, geoCircle, geoGraticule, geoArea } =
  await import(pathToFileURL(packageRoot + "/src/index.js").href)
const input = process.argv[2]
if (!input) throw new Error("Provide the exported display-only land GeoJSON")
const source = readFileSync(input, "utf8")
const land = JSON.parse(source)
// RFC7946 and D3 use opposite exterior winding conventions on the sphere.
for (const polygon of land.geometry.coordinates) {
  if (geoArea({ type: "Polygon", coordinates: polygon }) > 2 * Math.PI)
    polygon.forEach((ring) => ring.reverse())
}
const polarLatitude = 66.56
function rectangle(west, south, east, north) {
  const points = []
  for (let lon = west; lon < east; lon += 3) points.push([lon, south])
  for (let lat = south; lat < north; lat += 3) points.push([east, lat])
  for (let lon = east; lon > west; lon -= 3) points.push([lon, north])
  for (let lat = north; lat > south; lat -= 3) points.push([west, lat])
  points.push(points[0])
  const polygon = { type: "Polygon", coordinates: [points] }
  if (geoArea(polygon) > 2 * Math.PI) points.reverse()
  return polygon
}
const regions = {
  north: geoCircle().center([0, 90]).radius(90).precision(1)(),
  south: geoCircle().center([0, -90]).radius(90).precision(1)(),
  east: geoCircle().center([90, 0]).radius(90).precision(1)(),
  west: geoCircle().center([-90, 0]).radius(90).precision(1)(),
  ne: rectangle(0, 0, 180, 90),
  nw: rectangle(-180, 0, 0, 90),
  se: rectangle(0, -90, 180, 0),
  sw: rectangle(-180, -90, 0, 0),
  arctic: geoCircle()
    .center([0, 90])
    .radius(90 - polarLatitude)
    .precision(1)(),
  antarctic: geoCircle()
    .center([0, -90])
    .radius(90 - polarLatitude)
    .precision(1)(),
}
const views = {}
for (const [name, latitude] of [
  ["equatorial", 0],
  ["arctic", 55],
  ["antarctic", -55],
]) {
  const projection = geoOrthographic()
    .rotate([0, -latitude])
    .translate([0, 0])
    .scale(43)
    .precision(0.08)
  const path = geoPath(projection).digits(3)
  const boundary = {
    type: "MultiLineString",
    coordinates: [
      Array.from({ length: 181 }, (_, i) => [i - 90, 0]),
      Array.from({ length: 181 }, (_, i) => [0, i - 90]),
    ],
  }
  views[name] = {
    sphere: path({ type: "Sphere" }),
    land: path(land),
    graticule: path(geoGraticule().step([30, 30])()),
    axes: path(boundary),
    equator: path({ type: "LineString", coordinates: boundary.coordinates[0] }),
    meridian: path({
      type: "LineString",
      coordinates: boundary.coordinates[1],
    }),
    regions: Object.fromEntries(
      Object.entries(regions).map(([key, value]) => [key, path(value) || ""]),
    ),
  }
}
for (const view of Object.values(views)) {
  for (const value of [
    view.sphere,
    view.land,
    view.graticule,
    view.axes,
    ...Object.values(view.regions),
  ]) {
    if (value.replace(/[MLZ0-9eE+.,\s-]/g, ""))
      throw new Error("Unsupported SVG command")
  }
}
const output = {
  version: 1,
  projection: "orthographic",
  generator: "d3-geo@" + version,
  source: land.properties,
  source_sha256: createHash("sha256").update(source).digest("hex"),
  polar_latitude: polarLatitude,
  views,
}
writeFileSync(
  "lib/assets/achievement_collections/globes.json",
  JSON.stringify(output) + "\n",
)
console.log(
  "Wrote three clipped globe views with continents, graticules and geographic regions",
)
