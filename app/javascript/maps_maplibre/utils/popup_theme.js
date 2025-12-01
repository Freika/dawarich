/**
 * Theme utilities for MapLibre popups
 * Provides consistent theming across all popup types
 */

/**
 * Get current theme from document
 * @returns {string} 'dark' or 'light'
 */
export function getCurrentTheme() {
  if (document.documentElement.getAttribute('data-theme') === 'dark' ||
      document.documentElement.classList.contains('dark')) {
    return 'dark'
  }
  return 'light'
}

/**
 * Get theme-aware color values
 * @param {string} theme - 'dark' or 'light'
 * @returns {Object} Color values for the theme
 */
export function getThemeColors(theme = getCurrentTheme()) {
  if (theme === 'dark') {
    return {
      // Background colors
      background: '#1f2937',
      backgroundAlt: '#374151',

      // Text colors
      textPrimary: '#f9fafb',
      textSecondary: '#d1d5db',
      textMuted: '#9ca3af',

      // Border colors
      border: '#4b5563',
      borderLight: '#374151',

      // Accent colors
      accent: '#3b82f6',
      accentHover: '#2563eb',

      // Badge colors
      badgeSuggested: { bg: '#713f12', text: '#fef3c7' },
      badgeConfirmed: { bg: '#065f46', text: '#d1fae5' }
    }
  } else {
    return {
      // Background colors
      background: '#ffffff',
      backgroundAlt: '#f9fafb',

      // Text colors
      textPrimary: '#111827',
      textSecondary: '#374151',
      textMuted: '#6b7280',

      // Border colors
      border: '#e5e7eb',
      borderLight: '#f3f4f6',

      // Accent colors
      accent: '#3b82f6',
      accentHover: '#2563eb',

      // Badge colors
      badgeSuggested: { bg: '#fef3c7', text: '#92400e' },
      badgeConfirmed: { bg: '#d1fae5', text: '#065f46' }
    }
  }
}

/**
 * Get base popup styles as inline CSS
 * @param {string} theme - 'dark' or 'light'
 * @returns {string} CSS string for inline styles
 */
export function getPopupBaseStyles(theme = getCurrentTheme()) {
  const colors = getThemeColors(theme)

  return `
    font-family: system-ui, -apple-system, sans-serif;
    background-color: ${colors.background};
    color: ${colors.textPrimary};
  `
}

/**
 * Get popup container class with theme
 * @param {string} baseClass - Base CSS class name
 * @param {string} theme - 'dark' or 'light'
 * @returns {string} Class name with theme
 */
export function getPopupClass(baseClass, theme = getCurrentTheme()) {
  return `${baseClass} ${baseClass}--${theme}`
}

/**
 * Listen for theme changes and update popup if needed
 * @param {Function} callback - Callback to execute on theme change
 * @returns {Function} Cleanup function to remove listener
 */
export function onThemeChange(callback) {
  const observer = new MutationObserver((mutations) => {
    mutations.forEach((mutation) => {
      if (mutation.type === 'attributes' &&
          (mutation.attributeName === 'data-theme' ||
           mutation.attributeName === 'class')) {
        callback(getCurrentTheme())
      }
    })
  })

  observer.observe(document.documentElement, {
    attributes: true,
    attributeFilter: ['data-theme', 'class']
  })

  return () => observer.disconnect()
}
