export function filterVisits(visits, { query = "", status = "all" } = {}) {
  const term = String(query || "")
    .trim()
    .toLowerCase()
  return visits.filter((visit) => {
    const matchesSearch =
      !term ||
      visit.name?.toLowerCase().includes(term) ||
      visit.place?.name?.toLowerCase().includes(term)
    const matchesStatus = status === "all" || visit.status === status
    return matchesSearch && matchesStatus
  })
}
