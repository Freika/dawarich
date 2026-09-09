// Horizontal placement for the replay photo stack.
//
// The stack sits in the map's top-left corner, which on the main map is already
// occupied by the button cluster. The trip map renders no cluster, so the offset
// has to be derived from what is actually on screen rather than hardcoded - and
// the cluster itself moves right when the settings panel opens.

export function stackLeftOffset({ container, cluster, base = 16, gap = 10 }) {
  if (!cluster || !cluster.width || !cluster.height) return base
  const clearsCluster = cluster.right - container.left + gap
  return Math.max(base, clearsCluster)
}
