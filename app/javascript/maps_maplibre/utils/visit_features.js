export function visitsToGeoJSON(visits) {
  return {
    type: "FeatureCollection",
    features: visits.flatMap((visit) => {
      const location = [visit.place, visit.area, visit.center].find(
        (candidate) =>
          candidate?.latitude != null && candidate?.longitude != null,
      )
      if (!location) return []

      return [
        {
          type: "Feature",
          geometry: {
            type: "Point",
            coordinates: [location.longitude, location.latitude],
          },
          properties: {
            id: visit.id,
            name: visit.display_name || visit.name,
            place_name: visit.place?.name,
            status: visit.status,
            started_at: visit.started_at,
            ended_at: visit.ended_at,
            duration: visit.duration,
          },
        },
      ]
    }),
  }
}
