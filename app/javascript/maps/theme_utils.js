// Theme utility functions for map controls and buttons

/**
 * Get theme-aware styles for map controls based on user theme
 * @param {string} userTheme - 'light' or 'dark'
 * @returns {Object} Object containing CSS properties for the theme
 */
export function getThemeStyles(userTheme) {
  if (userTheme === 'light') {
    return {
      backgroundColor: '#ffffff',
      color: '#000000',
      borderColor: '#e5e7eb',
      shadowColor: 'rgba(0, 0, 0, 0.1)'
    };
  } else {
    return {
      backgroundColor: '#374151',
      color: '#ffffff',
      borderColor: '#4b5563',
      shadowColor: 'rgba(0, 0, 0, 0.3)'
    };
  }
}

/**
 * Apply theme-aware styles to a control element
 * @param {HTMLElement} element - DOM element to style
 * @param {string} userTheme - 'light' or 'dark'
 * @param {Object} additionalStyles - Optional additional CSS properties
 */
export function applyThemeToControl(element, userTheme, additionalStyles = {}) {
  const themeStyles = getThemeStyles(userTheme);

  // Apply base theme styles
  element.style.backgroundColor = themeStyles.backgroundColor;
  element.style.color = themeStyles.color;
  element.style.border = `1px solid ${themeStyles.borderColor}`;
  element.style.boxShadow = `0 1px 4px ${themeStyles.shadowColor}`;

  // Apply any additional styles
  Object.assign(element.style, additionalStyles);
}

/**
 * Apply theme-aware styles to a button element
 * @param {HTMLElement} button - Button element to style
 * @param {string} userTheme - 'light' or 'dark'
 */
export function applyThemeToButton(button, userTheme) {
  applyThemeToControl(button, userTheme, {
    border: 'none',
    cursor: 'pointer'
  });

  // Add hover effects
  const themeStyles = getThemeStyles(userTheme);
  const hoverBg = userTheme === 'light' ? '#f3f4f6' : '#4b5563';

  button.addEventListener('mouseenter', () => {
    button.style.backgroundColor = hoverBg;
  });

  button.addEventListener('mouseleave', () => {
    button.style.backgroundColor = themeStyles.backgroundColor;
  });
}

/**
 * Apply theme-aware styles to a panel/container element
 * @param {HTMLElement} panel - Panel element to style
 * @param {string} userTheme - 'light' or 'dark'
 */
export function applyThemeToPanel(panel, userTheme) {
  applyThemeToControl(panel, userTheme, {
    borderRadius: '4px'
  });
}