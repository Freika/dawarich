export function waitForStyle(map, lifetime) {
  return new Promise((resolve) => {
    if (map.loaded()) return resolve()
    const clear = () => {
      map.off("style.load", ready)
      map.off("load", ready)
    }
    const ready = () => {
      clear()
      resolve()
    }
    map.once("style.load", ready)
    map.once("load", ready)
    lifetime.own(clear)
  })
}
