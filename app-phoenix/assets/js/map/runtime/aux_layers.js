export function createHostAuxLayers({
  map,
  reader,
  library,
  root,
  onError,
  replayActive,
}) {
  let family, photos, photoKey
  return {
    async update(config, { operation, signal }) {
      if (!family && config.familyEnabled) {
        const { createMapFamilyLayer } = await operation.wait(
          import("../family/host.js"),
        )
        operation.check()
        family = createMapFamilyLayer({ map, reader, library, root })
      }
      if (family) await operation.wait(family.update(config, { signal }))
      if (!config.photosEnabled) {
        photos?.remove()
        photos = null
        photoKey = null
      } else {
        const desired = JSON.stringify([
          config.range,
          config.epoch,
          config.locale,
        ])
        if (photoKey !== desired || !photos) {
          const module = await operation.wait(import("../layers/photos.js"))
          operation.check()
          photos?.remove()
          photos = new module.PhotosLayer(map, {
            reader,
            library,
            timezone: config.range.timezone,
            labels: config.photoLabels,
            onError,
          })
          photos.add()
          const status = await operation.wait(
            photos.load(config.range, { signal }),
          )
          operation.check()
          if (status !== "ready" && status !== "unconfigured") throw new Error()
          if (replayActive()) photos.hide()
          photoKey = desired
        }
      }
    },
    clear(config) {
      family?.clear(config)
    },
    get photos() {
      return photos
    },
    get family() {
      return family
    },
    destroy() {
      family?.destroy()
      photos?.remove()
    },
  }
}
