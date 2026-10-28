// Isolated synthetic MapLibre harness: node spec/browser/photo_cluster_gallery_server.mjs

import { readFile } from "node:fs/promises"
import { createServer } from "node:http"
import { extname, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const root = resolve(fileURLToPath(new URL("../..", import.meta.url)))
const en = await readFile(
  resolve(root, "config/locales/photo_cluster.en.yml"),
  "utf8",
)
const labels = Object.fromEntries(
  [...en.matchAll(/^ {6}(\w+): (".*")$/gm)].map(([, key, value]) => [
    key,
    JSON.parse(value),
  ]),
)
const html = `<!doctype html><html lang="en" data-theme="light"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Photo clusters — synthetic verification</title>
<link rel="stylesheet" href="/node_modules/maplibre-gl/dist/maplibre-gl.css"><link rel="stylesheet" href="/app/assets/stylesheets/maps_maplibre.css">
<style>body{margin:0;font-family:system-ui}#map{position:absolute;inset:60px 0 0}nav{display:flex;gap:8px;padding:10px}nav button{padding:8px}</style>
<script type="importmap">{"imports":{"maplibre-gl":"/node_modules/maplibre-gl/dist/maplibre-gl.mjs","i18n":"/app/javascript/i18n.js"}}</script>
<script type="application/json" id="i18n-translations">${JSON.stringify({ photo_cluster: labels, common: { unknown: "Unknown" }, search: { unknown_location: "Unknown location" }, map_info: { photo: "Photo", video: "Video", taken: "Taken", location: "Location", source: "Source" } })}</script>
<nav><button id="hide">Toggle photos</button><button id="update">Change date range</button><button id="style">Change style</button><button id="theme">Dark theme</button></nav><div id="map"></div>
<script type="module">
import * as maplibregl from 'maplibre-gl'
import { PhotosLayer } from '/app/javascript/maps_maplibre/layers/photos_layer.js'
const style = {version:8,sources:{},layers:[{id:'background',type:'background',paint:{'background-color':'#dce8df'}}]}
window.map = new maplibregl.Map({container:'map',style,center:[13.4,52.5],zoom:12,attributionControl:false})
window.features = Array.from({length:101},(_,i)=>({type:'Feature',geometry:{type:'Point',coordinates:[13.4,52.5]},properties:{id:'synthetic-'+i,thumbnail_url:'/api/v1/photos/synthetic-'+i+'/thumbnail.jpg?api_key=synthetic&source=immich',filename:i===0?'<img src=x onerror=alert(1)>.jpg':'Synthetic photo '+(i+1)+'.jpg',taken_at:'2026-10-01T12:00:00Z',source:'immich',city:'Synthetic city',type:'IMAGE'}}))
const single = {type:'Feature',geometry:{type:'Point',coordinates:[13.42,52.51]},properties:{...features[1].properties,id:'single',filename:'Single photo.jpg'}}
window.data = {type:'FeatureCollection',features:[...features,single]}
window.ready = new Promise(resolve=>map.on('load',async()=>{
  // Avoid external glyph requests in this offline test style; production retains count labels.
  window.layer = new PhotosLayer(map)
  const configs = layer.getLayerConfigs.bind(layer)
  layer.getLayerConfigs=()=>configs().filter(config=>config.type!=='symbol')
  await layer.add(data)
  map.once('idle',resolve)
}))
document.querySelector('#hide').onclick=()=>layer.visible?layer.hide():layer.show()
document.querySelector('#update').onclick=()=>layer.update(data)
document.querySelector('#style').onclick=()=>{layer.remove();map.once('style.load',async()=>{window.layer=new PhotosLayer(map);layer.getLayerConfigs=()=>[{id:'photos-clusters',type:'circle',source:layer.sourceId,filter:['has','point_count'],paint:{'circle-radius':25,'circle-color':'#3b82f6'}}];await layer.add(data)});map.setStyle(style,{diff:false})}
document.querySelector('#theme').onclick=()=>document.documentElement.dataset.theme=document.documentElement.dataset.theme==='dark'?'light':'dark'
</script></html>`
const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, "http://localhost")
    if (url.pathname === "/favicon.ico") {
      res.writeHead(204)
      res.end()
      return
    }
    if (url.pathname === "/") {
      res.setHeader("Content-Type", "text/html; charset=utf-8")
      res.end(html)
      return
    }
    if (url.pathname.startsWith("/api/v1/photos/")) {
      if (url.searchParams.get("api_key") !== "synthetic") {
        res.writeHead(401)
        res.end()
        return
      }
      const id = Number(url.pathname.match(/synthetic-(\d+)/)?.[1] || 0)
      res.setHeader("Content-Type", "image/svg+xml")
      res.end(
        `<svg xmlns="http://www.w3.org/2000/svg" width="180" height="180"><rect width="180" height="180" fill="hsl(${(id * 47) % 360} 45% 65%)"/><path d="M0 180L65 65L110 130L140 80L180 180" fill="#356657"/><circle cx="130" cy="40" r="18" fill="#fff0a0"/><text x="12" y="25" font-family="sans-serif" font-size="18">Photo ${id + 1}</text></svg>`,
      )
      return
    }
    const allowed = [
      "/app/javascript/",
      "/app/assets/stylesheets/",
      "/node_modules/maplibre-gl/dist/",
    ]
    if (!allowed.some((prefix) => url.pathname.startsWith(prefix))) {
      res.writeHead(404)
      res.end()
      return
    }
    let path = resolve(root, `.${url.pathname}`)
    if (!path.startsWith(`${root}/`)) {
      res.writeHead(403)
      res.end()
      return
    }
    if (!extname(path)) path += ".js"
    res.setHeader(
      "Content-Type",
      path.endsWith(".css") ? "text/css" : "text/javascript",
    )
    res.end(await readFile(path))
  } catch {
    res.writeHead(404)
    res.end()
  }
})
server.listen(Number(process.env.PHOTO_GALLERY_PORT || 8796), "127.0.0.1", () =>
  console.log(
    `Synthetic photo gallery: http://127.0.0.1:${server.address().port}`,
  ),
)
