export const SOURCE_ID = "protomaps"
export const DEFAULT_TILE_URL = "https://tyles.dwri.xyz/planet/{z}/{x}/{y}.mvt"
export const SOURCE_MAX_ZOOM = 15

export const PARK_KINDS = [
  "national_park",
  "park",
  "cemetery",
  "protected_area",
  "nature_reserve",
  "forest",
  "golf_course",
  "wood",
  "scrub",
  "grassland",
  "grass",
  "military",
  "naval_base",
  "airfield",
  "allotments",
  "village_green",
  "playground",
]

// Protomaps `roads` carries only coarse kinds (highway/major_road/minor_road/
// other/path), so the sidecar's primary/secondary/tertiary split collapses here:
// highway->motorway, major_road->primary, minor_road->residential, other/path->default.
// secondary/tertiary theme colors are intentionally unused (no matching tile kind).
export const ROAD_BUCKETS = [
  {
    id: "poster_roads_other",
    themeKey: "default",
    filter: ["in", "kind", "other", "path"],
    widthStops: [
      [12, 0.2],
      [15, 0.7],
      [16, 1.4],
    ],
  },
  {
    id: "poster_roads_minor",
    themeKey: "residential",
    filter: ["==", "kind", "minor_road"],
    widthStops: [
      [11, 0.3],
      [14, 0.9],
      [16, 2.2],
    ],
  },
  {
    id: "poster_roads_major",
    themeKey: "primary",
    filter: ["==", "kind", "major_road"],
    widthStops: [
      [6, 0.3],
      [12, 1.2],
      [16, 4],
    ],
  },
  {
    id: "poster_roads_highway",
    themeKey: "motorway",
    filter: ["==", "kind", "highway"],
    widthStops: [
      [5, 0.4],
      [10, 1.2],
      [14, 3.2],
      [16, 6],
    ],
  },
]
