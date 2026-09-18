# Spectral Cartogram materials

Ported from the Dawarich Spectral Cartogram playground, reference preset v15.
Two shared grayscale scans: `paper-pressed-fiber-v2.webp` (pressed cellulose)
and `foil-stamped-grain-v4.webp` (stamped metal). Combined: 1,720,152 bytes.
Both are native 1254 × 1254 generated images, not measured 4K material scans.
Generated with OpenAI image generation for this project; WebP quality 94, no resize.

The SVG renderer preserves the playground's directional paper convolution,
matte tonal transfer, overlay/color-dodge foil layers, spectral palette and
irregular refractive edge. Crops are deterministic per geographic key.
No country image, map tile, route or GPS point is baked into either asset.
The same two files serve the complete collection. Only visible cards hydrate
their materials, and pointer work stops entirely while idle/reduced-motion.

Geometry comes from the existing cached Natural Earth/geoBoundaries catalog.
The original source notes and material-generation prompts remain in the sibling
`spectral-cartogram-playground` directory. Runtime needs only these two WebPs.
