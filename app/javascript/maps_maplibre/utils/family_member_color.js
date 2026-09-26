const COLORS = [
  "#3b82f6",
  "#10b981",
  "#f59e0b",
  "#ef4444",
  "#8b5cf6",
  "#ec4899",
]

export function familyMemberColor(userId) {
  const hash = String(userId)
    .split("")
    .reduce((sum, char) => sum + char.charCodeAt(0), 0)
  return COLORS[hash % COLORS.length]
}
