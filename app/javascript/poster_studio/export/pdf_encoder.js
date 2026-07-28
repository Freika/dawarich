const PT_PER_MM = 72 / 25.4
const enc = (s) => new TextEncoder().encode(s)

function canvasToJpeg(canvas, quality) {
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (blob) =>
        blob
          ? blob.arrayBuffer().then((b) => resolve(new Uint8Array(b)))
          : reject(new Error("toBlob failed")),
      "image/jpeg",
      quality,
    )
  })
}

// Minimal single-page PDF: one DCTDecode (JPEG) image scaled to fill the page at
// the exact physical paper size. Opaque poster, so no alpha/SMask needed.
export async function encodePdf(canvas, { widthMm, heightMm, quality = 0.92 }) {
  const jpeg = await canvasToJpeg(canvas, quality)
  const wpt = +(widthMm * PT_PER_MM).toFixed(2)
  const hpt = +(heightMm * PT_PER_MM).toFixed(2)
  const iw = canvas.width
  const ih = canvas.height

  const parts = []
  let len = 0
  const offsets = []
  const push = (b) => {
    const bytes = typeof b === "string" ? enc(b) : b
    parts.push(bytes)
    len += bytes.length
  }
  const obj = (num, body) => {
    offsets[num] = len
    push(`${num} 0 obj\n`)
    for (const b of body) push(b)
    push("\nendobj\n")
  }

  push("%PDF-1.4\n")
  push(Uint8Array.from([0x25, 0xff, 0xff, 0xff, 0xff, 0x0a]))

  obj(1, ["<< /Type /Catalog /Pages 2 0 R >>"])
  obj(2, ["<< /Type /Pages /Kids [3 0 R] /Count 1 >>"])
  obj(3, [
    `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${wpt} ${hpt}] /Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>`,
  ])
  obj(4, [
    `<< /Type /XObject /Subtype /Image /Width ${iw} /Height ${ih} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${jpeg.length} >>\nstream\n`,
    jpeg,
    "\nendstream",
  ])
  const content = `q\n${wpt} 0 0 ${hpt} 0 0 cm\n/Im0 Do\nQ\n`
  obj(5, [`<< /Length ${content.length} >>\nstream\n${content}endstream`])

  const xrefOffset = len
  let xref = "xref\n0 6\n0000000000 65535 f \n"
  for (let i = 1; i <= 5; i += 1) {
    xref += `${String(offsets[i]).padStart(10, "0")} 00000 n \n`
  }
  push(xref)
  push(`trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n${xrefOffset}\n%%EOF\n`)

  const out = new Uint8Array(len)
  let offset = 0
  for (const p of parts) {
    out.set(p, offset)
    offset += p.length
  }
  return out
}
