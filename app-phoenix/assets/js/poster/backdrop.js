export function createBackdrop(image, { URL = globalThis.URL } = {}) {
  let url = null
  let generation = 0

  return {
    update(canvas) {
      if (!image) return
      const current = generation
      canvas.toBlob(
        (blob) => {
          if (!blob || current !== generation) return
          const previous = url
          url = URL.createObjectURL(blob)
          image.src = url
          image.classList.remove("opacity-0")
          if (previous) URL.revokeObjectURL(previous)
        },
        "image/jpeg",
        0.5,
      )
    },
    release() {
      generation++
      if (!image) return
      image.classList.add("opacity-0")
      image.removeAttribute("src")
      if (url) URL.revokeObjectURL(url)
      url = null
    },
  }
}
