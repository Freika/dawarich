export function photoMarkers(map, library, photos) {
  const markers = []
  for (const photo of photos) {
    if (
      photo.latitude == null ||
      photo.longitude == null ||
      !photo.thumbnail_url?.startsWith("/api/v1/shared/")
    )
      continue
    const image = document.createElement("img")
    image.src = photo.thumbnail_url
    image.loading = "lazy"
    image.alt = ""
    image.className =
      "shared-photo-marker rounded-full border-2 border-white shadow"
    Object.assign(image.style, {
      width: "32px",
      height: "32px",
      objectFit: "cover",
    })
    markers.push(
      new library.Marker({ element: image })
        .setLngLat([photo.longitude, photo.latitude])
        .addTo(map),
    )
  }
  return markers
}
