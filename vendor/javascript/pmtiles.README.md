# PMTiles for Browsers + NodeJS

See the [JavaScript API docs](https://pmtiles.io/typedoc/)

the [PMTiles](https://www.npmjs.com/package/pmtiles) package can be included via script tag or ES6 module:

```html
 <script src="https://unpkg.com/pmtiles@<VERSION>/dist/pmtiles.js"></script>
```

All the PMTiles exports are available under the global `pmtiles` variable e.g. `pmtiles.PMTiles`.

As an ES6 module: `npm add pmtiles`

```js
import { PMTiles } from "pmtiles";
```

### Leaflet: Raster tileset

Example of a raster PMTiles archive displayed in Leaflet:

```js
import { PMTiles, leafletRasterLayer } from "pmtiles";
const p = new PMTiles('example.pmtiles')
leafletRasterLayer(p,{attribution:'© <a href="https://openstreetmap.org">OpenStreetMap</a>'}).addTo(map)
````

[Live example](https://pmtiles.io/examples/leaflet.html) | [Code](https://github.com/protomaps/PMTiles/blob/main/js/examples/leaflet.html)

### Leaflet: Vector tileset

See [protomaps-leaflet](https://github.com/protomaps/protomaps-leaflet)

## MapLibre GL JS

Example of a PMTiles archive displayed in MapLibre GL JS:

```js
import { Protocol } from "pmtiles";
let protocol = new Protocol();
maplibregl.addProtocol("pmtiles",protocol.tile);
var style = {
"version": 8,
"sources": {
    "example_source": {
        "type": "vector",
        "url": "pmtiles://https://example.com/example.pmtiles",
        "attribution": '© <a href="https://openstreetmap.org">OpenStreetMap</a>'
    ...
```

[Live example](https://pmtiles.io/examples/maplibre.html) | [Code](https://github.com/protomaps/PMTiles/blob/main/js/examples/maplibre.html)

# CORS

See the [Protomaps Docs on Cloud Storage](https://protomaps.com/docs/pmtiles/cloud-storage) for uploading and configuring CORS for Cloudflare R2, Amazon S3, Google Cloud Storage and more.
