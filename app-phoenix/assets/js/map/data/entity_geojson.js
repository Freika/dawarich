import { createCircle } from "../algorithms/geometry.js";
export function visitsToGeoJSON(visits) {
  return {
    type: "FeatureCollection",
    features: visits.map((visit) => ({
      type: "Feature",
      geometry: {
        type: "Point",
        coordinates: [visit.place.longitude, visit.place.latitude],
      },
      properties: {
        id: visit.id,
        name: visit.name,
        place_name: visit.place?.name,
        status: visit.status,
        started_at: visit.started_at,
        ended_at: visit.ended_at,
        duration: visit.duration,
      },
    })),
  };
}
export function placesToGeoJSON(places) {
  return {
    type: "FeatureCollection",
    features: places.map((place) => ({
      type: "Feature",
      geometry: {
        type: "Point",
        coordinates: [place.longitude, place.latitude],
      },
      properties: {
        id: place.id,
        name: place.name,
        latitude: place.latitude,
        longitude: place.longitude,
        note: place.note,
        nameLocked: Boolean(place.name_locked),
        tags: JSON.stringify(place.tags || []),
        color: place.tags?.[0]?.color || "#6366f1",
      },
    })),
  };
}
export function areasToGeoJSON(areas) {
  return {
    type: "FeatureCollection",
    features: areas.map((area) => {
      const center = [parseFloat(area.longitude), parseFloat(area.latitude)];
      const coordinates = createCircle(center, area.radius);

      return {
        type: "Feature",
        geometry: {
          type: "Polygon",
          coordinates: [coordinates],
        },
        properties: {
          id: area.id,
          name: area.name,
          color: area.color || "#ef4444",
          radius: area.radius,
          latitude: center[1],
          longitude: center[0],
        },
      };
    }),
  };
}
