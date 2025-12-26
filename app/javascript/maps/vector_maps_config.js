/**
 * Vector maps configuration for Maps V1 (legacy)
 * For Maps V2, use style_manager.js instead
 */
export const mapsConfig = {
    "Light": {
      url: "https://tyles.dwri.xyz/planet/{z}/{x}/{y}.mvt",
      flavor: "light",
      maxZoom: 14,
      attribution: "<a href='https://github.com/protomaps/basemaps'>Protomaps</a>, &copy; <a href='https://openstreetmap.org'>OpenStreetMap</a>"
    },
    "Dark": {
      url: "https://tyles.dwri.xyz/planet/{z}/{x}/{y}.mvt",
      flavor: "dark",
      maxZoom: 14,
      attribution: "<a href='https://github.com/protomaps/basemaps'>Protomaps</a>, &copy; <a href='https://openstreetmap.org'>OpenStreetMap</a>"
    },
    "White": {
      url: "https://tyles.dwri.xyz/planet/{z}/{x}/{y}.mvt",
      flavor: "white",
      maxZoom: 14,
      attribution: "<a href='https://github.com/protomaps/basemaps'>Protomaps</a>, &copy; <a href='https://openstreetmap.org'>OpenStreetMap</a>"
    },
    "Grayscale": {
      url: "https://tyles.dwri.xyz/planet/{z}/{x}/{y}.mvt",
      flavor: "grayscale",
      maxZoom: 14,
      attribution: "<a href='https://github.com/protomaps/basemaps'>Protomaps</a>, &copy; <a href='https://openstreetmap.org'>OpenStreetMap</a>"
    },
    "Black": {
      url: "https://tyles.dwri.xyz/planet/{z}/{x}/{y}.mvt",
      flavor: "black",
      maxZoom: 14,
      attribution: "<a href='https://github.com/protomaps/basemaps'>Protomaps</a>, &copy; <a href='https://openstreetmap.org'>OpenStreetMap</a>"
    },
};
