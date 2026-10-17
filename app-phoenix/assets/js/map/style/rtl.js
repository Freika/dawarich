const pending = new WeakMap()
export function registerRTLTextPlugin(
  library,
  pluginURL,
  { onError = () => {} } = {},
) {
  if (pending.has(library)) return pending.get(library)
  const status = library.getRTLTextPluginStatus()
  if (
    !["unavailable", "requested"].includes(status) ||
    typeof pluginURL !== "string" ||
    !pluginURL
  )
    return Promise.resolve(false)
  const request = Promise.resolve()
    .then(() => library.setRTLTextPlugin(pluginURL, true))
    .then(
      () => true,
      () => {
        pending.delete(library)
        onError("rtl_unavailable")
        return false
      },
    )
  pending.set(library, request)
  return request
}
