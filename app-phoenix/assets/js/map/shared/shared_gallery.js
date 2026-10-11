export { clearGalleries } from "./shared_erase.js"

function images(content, photos) {
  content.replaceChildren()
  for (const photo of photos) {
    if (!photo.thumbnail_url?.startsWith("/api/v1/shared/")) continue
    const image = document.createElement("img")
    image.src = photo.thumbnail_url
    image.alt = ""
    image.loading = "lazy"
    image.className = "aspect-square rounded-lg object-cover w-full"
    content.append(image)
  }
}

export function openGallery(details) {
  if (!details.open) return
  const content = details.querySelector("[data-public-gallery-content]")
  if (content) images(content, details.publicPhotos || [])
}

export function showGallery(el, photos, _zone) {
  const content = el.querySelector(
    "div[data-public-gallery][data-public-gallery-content]",
  )
  if (content) images(content, photos)
  for (const details of el.querySelectorAll("details[data-public-gallery]")) {
    details.publicPhotos = photos.filter((photo) => {
      return photo.day_key === details.dataset.publicGalleryDay
    })
    openGallery(details)
  }
}
