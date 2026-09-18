export function appUrl(path) {
  const root =
    document.querySelector('meta[name="relative-url-root"]')?.content ?? ""
  return `${root}${path}`
}
