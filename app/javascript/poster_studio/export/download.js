export function downloadBlob(blob, filename) {
  const url = URL.createObjectURL(blob)
  const link = document.createElement("a")
  link.href = url
  link.download = filename
  document.body.appendChild(link)
  link.click()
  link.remove()
  setTimeout(() => URL.revokeObjectURL(url), 2000)
}

export function pngBlob(bytes) {
  return new Blob([bytes], { type: "image/png" })
}

export function pdfBlob(bytes) {
  return new Blob([bytes], { type: "application/pdf" })
}

export function posterFilename(theme, paperKey, extension) {
  const slug = (theme?.name ?? "poster")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "")
  return `dawarich-poster-${slug}-${paperKey}.${extension}`
}
