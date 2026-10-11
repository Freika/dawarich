export function stackLeftOffset({ container, cluster, base = 16, gap = 10 }) {
  if (!cluster || !cluster.width || !cluster.height) return base
  const clearsCluster = cluster.right - container.left + gap
  return Math.max(base, clearsCluster)
}
