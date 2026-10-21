import { mapTranslate } from "./translate.js"

export function mapNotify(getConfig) {
  const translate = mapTranslate(getConfig)
  return async (type, key, bindings = {}, duration) => {
    const document = globalThis.document
    if (!document?.body) return
    const { Toast } = await import("./toast.js")
    if (globalThis.document !== document) return
    return Toast[type](translate(key, bindings), duration)
  }
}
