// Dynamic CSS injection for theme-aware Leaflet controls
export function injectThemeStyles(userTheme) {
  // Remove existing theme styles if any
  const existingStyle = document.getElementById('leaflet-theme-styles');
  if (existingStyle) {
    existingStyle.remove();
  }

  const themeColors = getThemeColors(userTheme);

  const css = `
    /* Leaflet default controls theme override */
    .leaflet-control-layers,
    .leaflet-control-zoom,
    .leaflet-control-attribution,
    .leaflet-bar a,
    .leaflet-control-layers-toggle,
    .leaflet-control-layers-list,
    .leaflet-control-draw {
      background-color: ${themeColors.backgroundColor} !important;
      color: ${themeColors.textColor} !important;
      border-color: ${themeColors.borderColor} !important;
      box-shadow: 0 1px 4px ${themeColors.shadowColor} !important;
    }

    /* Leaflet zoom buttons */
    .leaflet-control-zoom a {
      background-color: ${themeColors.backgroundColor} !important;
      color: ${themeColors.textColor} !important;
      border-bottom: 1px solid ${themeColors.borderColor} !important;
    }

    .leaflet-control-zoom a:hover {
      background-color: ${themeColors.hoverColor} !important;
    }

    /* Leaflet layer control */
    .leaflet-control-layers-toggle {
      background-color: ${themeColors.backgroundColor} !important;
      color: ${themeColors.textColor} !important;
    }

    .leaflet-control-layers-expanded {
      background-color: ${themeColors.backgroundColor} !important;
      color: ${themeColors.textColor} !important;
    }

    .leaflet-control-layers label {
      color: ${themeColors.textColor} !important;
    }

    /* Leaflet Draw controls */
    .leaflet-draw-toolbar a {
      background-color: ${themeColors.backgroundColor} !important;
      color: ${themeColors.textColor} !important;
      border-bottom: 1px solid ${themeColors.borderColor} !important;
    }

    .leaflet-draw-toolbar a:hover {
      background-color: ${themeColors.hoverColor} !important;
    }

    .leaflet-draw-actions a {
      background-color: ${themeColors.backgroundColor} !important;
      color: ${themeColors.textColor} !important;
    }

    /* Leaflet popups */
    .leaflet-popup-content-wrapper {
      background-color: ${themeColors.backgroundColor} !important;
      color: ${themeColors.textColor} !important;
    }

    .leaflet-popup-tip {
      background-color: ${themeColors.backgroundColor} !important;
    }

    /* Attribution control */
    .leaflet-control-attribution a {
      color: ${userTheme === 'light' ? '#0066cc' : '#66b3ff'} !important;
    }

    /* Custom control buttons */
    .leaflet-control-button,
    .add-visit-button,
    .leaflet-bar button {
      background-color: ${themeColors.backgroundColor} !important;
      color: ${themeColors.textColor} !important;
      border: 1px solid ${themeColors.borderColor} !important;
      box-shadow: 0 1px 4px ${themeColors.shadowColor} !important;
    }

    .leaflet-control-button:hover,
    .add-visit-button:hover,
    .leaflet-bar button:hover {
      background-color: ${themeColors.hoverColor} !important;
    }

    /* Any other custom controls */
    .leaflet-top .leaflet-control button,
    .leaflet-bottom .leaflet-control button,
    .leaflet-left .leaflet-control button,
    .leaflet-right .leaflet-control button {
      background-color: ${themeColors.backgroundColor} !important;
      color: ${themeColors.textColor} !important;
      border: 1px solid ${themeColors.borderColor} !important;
    }

    /* Location search button */
    .location-search-toggle,
    #location-search-toggle {
      background-color: ${themeColors.backgroundColor} !important;
      color: ${themeColors.textColor} !important;
      border: 1px solid ${themeColors.borderColor} !important;
      box-shadow: 0 1px 4px ${themeColors.shadowColor} !important;
    }

    .location-search-toggle:hover,
    #location-search-toggle:hover {
      background-color: ${themeColors.hoverColor} !important;
    }

    /* Distance scale control - minimal theming to avoid duplication */
    .leaflet-control-scale {
      background: rgba(${userTheme === 'light' ? '255, 255, 255' : '55, 65, 81'}, 0.9) !important;
      border-radius: 3px !important;
      padding: 2px !important;
    }
  `;

  // Inject the CSS
  const style = document.createElement('style');
  style.id = 'leaflet-theme-styles';
  style.textContent = css;
  document.head.appendChild(style);
}

function getThemeColors(userTheme) {
  if (userTheme === 'light') {
    return {
      backgroundColor: '#ffffff',
      textColor: '#000000',
      borderColor: '#e5e7eb',
      shadowColor: 'rgba(0, 0, 0, 0.1)',
      hoverColor: '#f3f4f6'
    };
  } else {
    return {
      backgroundColor: '#374151',
      textColor: '#ffffff',
      borderColor: '#4b5563',
      shadowColor: 'rgba(0, 0, 0, 0.3)',
      hoverColor: '#4b5563'
    };
  }
}
