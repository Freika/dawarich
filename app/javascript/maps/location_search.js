// Location search functionality for the map
class LocationSearch {
  constructor(map, apiKey) {
    this.map = map;
    this.apiKey = apiKey;
    this.searchResults = [];
    this.searchMarkersLayer = null;
    this.currentSearchQuery = '';
    this.searchTimeout = null;
    this.suggestionsVisible = false;
    this.currentSuggestionIndex = -1;

    this.initializeSearchBar();
  }

  initializeSearchBar() {
    // Create search toggle button using Leaflet control (positioned below settings button)
    const SearchToggleControl = L.Control.extend({
      onAdd: function(map) {
        const button = L.DomUtil.create('button', 'location-search-toggle');
        button.innerHTML = '🔍';
        button.style.width = '48px';
        button.style.height = '48px';
        button.style.border = 'none';
        button.style.cursor = 'pointer';
        button.style.boxShadow = '0 1px 4px rgba(0,0,0,0.3)';
        button.style.backgroundColor = 'white';
        button.style.borderRadius = '4px';
        button.style.padding = '0';
        button.style.fontSize = '18px';
        button.style.marginTop = '10px'; // Space below settings button
        button.title = 'Search locations';
        button.id = 'location-search-toggle';
        return button;
      }
    });

    // Add the search toggle control to the map
    this.map.addControl(new SearchToggleControl({ position: 'topleft' }));

    // Use setTimeout to ensure the DOM element is available
    setTimeout(() => {
      // Get reference to the created button
      const toggleButton = document.getElementById('location-search-toggle');
      
      if (toggleButton) {
        // Create inline search bar
        this.createInlineSearchBar();

        // Store references
        this.toggleButton = toggleButton;
        this.searchVisible = false;

        // Bind events
        this.bindSearchEvents();
        
        console.log('LocationSearch: Search button initialized successfully');
      } else {
        console.error('LocationSearch: Could not find search toggle button');
      }
    }, 100);
  }

  createInlineSearchBar() {
    // Create inline search bar that appears next to the search button
    const searchBar = document.createElement('div');
    searchBar.className = 'location-search-bar absolute bg-white border border-gray-300 rounded-lg shadow-lg';
    searchBar.id = 'location-search-bar';
    searchBar.style.width = '300px';
    searchBar.style.padding = '8px';
    searchBar.style.display = 'none'; // Start hidden with inline style instead of class
    searchBar.style.zIndex = '9999'; // Very high z-index to ensure visibility

    searchBar.innerHTML = `
      <div class="flex items-center space-x-2">
        <input 
          type="text" 
          placeholder="Search locations..." 
          class="flex-1 px-3 py-2 border border-gray-300 rounded focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent text-sm"
          id="location-search-input"
        />
        <button 
          id="location-search-submit" 
          class="px-3 py-2 bg-blue-500 text-white rounded hover:bg-blue-600 text-sm"
        >
          Search
        </button>
        <button 
          id="location-search-close" 
          class="px-2 py-2 text-gray-400 hover:text-gray-600"
        >
          ✕
        </button>
      </div>
      
      <!-- Suggestions dropdown -->
      <div id="location-search-suggestions-panel" class="hidden mt-2">
        <div class="bg-gray-50 px-3 py-2 border-b text-xs font-medium text-gray-700">Suggestions</div>
        <div id="location-search-suggestions" class="max-h-48 overflow-y-auto"></div>
      </div>
      
      <!-- Results dropdown -->
      <div id="location-search-results-panel" class="hidden mt-2">
        <div class="bg-gray-50 px-3 py-2 border-b text-xs font-medium text-gray-700">Results</div>
        <div id="location-search-results" class="max-h-64 overflow-y-auto"></div>
      </div>
    `;

    // Add search bar to the map container
    this.map.getContainer().appendChild(searchBar);

    // Store references
    this.searchBar = searchBar;
    this.searchInput = document.getElementById('location-search-input');
    this.searchButton = document.getElementById('location-search-submit');
    this.closeButton = document.getElementById('location-search-close');
    this.suggestionsContainer = document.getElementById('location-search-suggestions');
    this.suggestionsPanel = document.getElementById('location-search-suggestions-panel');
    this.resultsContainer = document.getElementById('location-search-results');
    this.resultsPanel = document.getElementById('location-search-results-panel');
    
    // No clear button or default panel in inline mode
    this.clearButton = null;
    this.defaultPanel = null;
  }


  bindSearchEvents() {
    // Toggle search bar visibility
    this.toggleButton.addEventListener('click', (e) => {
      console.log('Search button clicked!');
      e.preventDefault();
      e.stopPropagation();
      this.showSearchBar();
    });

    // Close search bar
    this.closeButton.addEventListener('click', () => {
      this.hideSearchBar();
    });

    // Search on button click
    this.searchButton.addEventListener('click', () => {
      this.performSearch();
    });

    // Search on Enter key
    this.searchInput.addEventListener('keypress', (e) => {
      if (e.key === 'Enter') {
        if (this.suggestionsVisible && this.currentSuggestionIndex >= 0) {
          this.selectSuggestion(this.currentSuggestionIndex);
        } else {
          this.performSearch();
        }
      }
    });

    // Clear search (no clear button in inline mode, handled by close button)

    // Handle real-time suggestions
    this.searchInput.addEventListener('input', (e) => {
      const query = e.target.value.trim();
      
      if (query.length > 0) {
        this.debouncedSuggestionSearch(query);
      } else {
        this.hideSuggestions();
        this.showDefaultState();
      }
    });

    // Handle keyboard navigation for suggestions
    this.searchInput.addEventListener('keydown', (e) => {
      if (this.suggestionsVisible) {
        switch (e.key) {
          case 'ArrowDown':
            e.preventDefault();
            this.navigateSuggestions(1);
            break;
          case 'ArrowUp':
            e.preventDefault();
            this.navigateSuggestions(-1);
            break;
          case 'Escape':
            this.hideSuggestions();
            this.showDefaultState();
            break;
        }
      }
    });

    // Close sidepanel on Escape key
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && this.searchVisible) {
        this.hideSearchBar();
      }
    });

    // Close search bar when clicking outside
    document.addEventListener('click', (e) => {
      if (this.searchVisible && 
          !e.target.closest('.location-search-bar') &&
          !e.target.closest('#location-search-toggle')) {
        this.hideSearchBar();
      }
    });
  }

  async performSearch() {
    const query = this.searchInput.value.trim();
    if (!query) return;

    this.currentSearchQuery = query;
    this.showLoading();

    try {
      const response = await fetch(`/api/v1/locations?q=${encodeURIComponent(query)}`, {
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json'
        }
      });

      if (!response.ok) {
        throw new Error(`Search failed: ${response.status} ${response.statusText}`);
      }

      const data = await response.json();
      this.displaySearchResults(data);

    } catch (error) {
      console.error('Location search error:', error);
      this.showError('Failed to search locations. Please try again.');
    }
  }

  showLoading() {
    // Hide other panels and show results with loading
    this.suggestionsPanel.classList.add('hidden');
    this.resultsPanel.classList.remove('hidden');

    this.resultsContainer.innerHTML = `
      <div class="p-8 text-center">
        <div class="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500"></div>
        <div class="text-sm text-gray-600 mt-3">Searching for "${this.currentSearchQuery}"...</div>
      </div>
    `;
  }

  showError(message) {
    // Hide other panels and show results with error
    this.suggestionsPanel.classList.add('hidden');
    this.resultsPanel.classList.remove('hidden');

    this.resultsContainer.innerHTML = `
      <div class="p-8 text-center">
        <div class="text-4xl mb-3">⚠️</div>
        <div class="text-sm font-medium text-red-600 mb-2">Search Failed</div>
        <div class="text-xs text-gray-500">${message}</div>
      </div>
    `;
  }

  displaySearchResults(data) {
    // Hide other panels and show results
    this.suggestionsPanel.classList.add('hidden');
    this.resultsPanel.classList.remove('hidden');

    if (!data.locations || data.locations.length === 0) {
      this.resultsContainer.innerHTML = `
        <div class="p-6 text-center text-gray-500">
          <div class="text-3xl mb-3">📍</div>
          <div class="text-sm font-medium">No visits found</div>
          <div class="text-xs mt-1">No visits found for "${this.currentSearchQuery}"</div>
        </div>
      `;
      return;
    }

    this.searchResults = data.locations;
    this.clearSearchMarkers();

    let resultsHtml = `
      <div class="p-4 border-b bg-gray-50">
        <div class="text-sm font-medium text-gray-700">Found ${data.total_locations} location(s)</div>
        <div class="text-xs text-gray-500 mt-1">for "${this.currentSearchQuery}"</div>
      </div>
    `;

    data.locations.forEach((location, index) => {
      resultsHtml += this.buildLocationResultHtml(location, index);
    });

    this.resultsContainer.innerHTML = resultsHtml;

    // Add markers to map
    this.addSearchMarkersToMap(data.locations);

    // Bind result interaction events
    this.bindResultEvents();
  }

  buildLocationResultHtml(location, index) {
    const firstVisit = location.visits[0];
    const lastVisit = location.visits[location.visits.length - 1];
    
    // Group visits by year
    const visitsByYear = this.groupVisitsByYear(location.visits);
    
    return `
      <div class="location-result border-b" data-location-index="${index}">
        <div class="p-4">
          <div class="font-medium text-sm">${this.escapeHtml(location.place_name)}</div>
          <div class="text-xs text-gray-600 mt-1">${this.escapeHtml(location.address || '')}</div>
          <div class="flex justify-between items-center mt-3">
            <div class="text-xs text-blue-600">${location.total_visits} visit(s)</div>
            <div class="text-xs text-gray-500">
              first ${this.formatDateShort(firstVisit.date)}, last ${this.formatDateShort(lastVisit.date)}
            </div>
          </div>
        </div>
        
        <!-- Years Section -->
        <div class="border-t bg-gray-50">
          ${Object.entries(visitsByYear).map(([year, yearVisits]) => `
            <div class="year-section">
              <div class="year-toggle p-3 hover:bg-gray-100 cursor-pointer border-b border-gray-200 flex justify-between items-center" 
                   data-location-index="${index}" data-year="${year}">
                <span class="text-sm font-medium text-gray-700">${year}</span>
                <span class="text-xs text-blue-600">${yearVisits.length} visits</span>
                <span class="year-arrow text-gray-400 transition-transform">▶</span>
              </div>
              <div class="year-visits hidden" id="year-${index}-${year}">
                ${yearVisits.map((visit, visitIndex) => `
                  <div class="visit-item text-xs text-gray-700 py-2 px-4 border-b border-gray-100 hover:bg-blue-50 cursor-pointer" 
                       data-location-index="${index}" data-visit-index="${location.visits.indexOf(visit)}">
                    <div class="flex justify-between items-start">
                      <div>
                        📍 ${this.formatDateTime(visit.date)}
                        <div class="text-xs text-gray-500 mt-1">
                          ${visit.duration_estimate}
                        </div>
                      </div>
                      <div class="text-xs text-gray-400">
                        ${visit.distance_meters}m
                      </div>
                    </div>
                  </div>
                `).join('')}
              </div>
            </div>
          `).join('')}
        </div>
      </div>
    `;
  }

  groupVisitsByYear(visits) {
    const groups = {};
    visits.forEach(visit => {
      const year = new Date(visit.date).getFullYear().toString();
      if (!groups[year]) {
        groups[year] = [];
      }
      groups[year].push(visit);
    });
    
    // Sort years descending (most recent first)
    const sortedGroups = {};
    Object.keys(groups)
      .sort((a, b) => parseInt(b) - parseInt(a))
      .forEach(year => {
        sortedGroups[year] = groups[year];
      });
    
    return sortedGroups;
  }

  formatDateShort(dateString) {
    const date = new Date(dateString);
    return date.toLocaleDateString('en-GB', {
      day: '2-digit',
      month: '2-digit', 
      year: 'numeric'
    });
  }

  bindResultEvents() {
    // Bind click events to year toggles
    const yearToggles = this.resultsContainer.querySelectorAll('.year-toggle');
    yearToggles.forEach(toggle => {
      toggle.addEventListener('click', (e) => {
        e.stopPropagation();
        const locationIndex = parseInt(toggle.dataset.locationIndex);
        const year = toggle.dataset.year;
        this.toggleYear(locationIndex, year, toggle);
      });
    });

    // Bind click events to individual visits
    const visitResults = this.resultsContainer.querySelectorAll('.visit-item');
    visitResults.forEach(visit => {
      visit.addEventListener('click', (e) => {
        e.stopPropagation(); // Prevent triggering other clicks
        const locationIndex = parseInt(visit.dataset.locationIndex);
        const visitIndex = parseInt(visit.dataset.visitIndex);
        this.focusOnVisit(this.searchResults[locationIndex], visitIndex);
      });
    });
  }

  toggleYear(locationIndex, year, toggleElement) {
    const yearVisitsContainer = document.getElementById(`year-${locationIndex}-${year}`);
    const arrow = toggleElement.querySelector('.year-arrow');
    
    if (yearVisitsContainer.classList.contains('hidden')) {
      // Show visits
      yearVisitsContainer.classList.remove('hidden');
      arrow.style.transform = 'rotate(90deg)';
      arrow.textContent = '▼';
    } else {
      // Hide visits
      yearVisitsContainer.classList.add('hidden');
      arrow.style.transform = 'rotate(0deg)';
      arrow.textContent = '▶';
    }
  }

  addSearchMarkersToMap(locations) {
    if (this.searchMarkersLayer) {
      this.map.removeLayer(this.searchMarkersLayer);
    }

    this.searchMarkersLayer = L.layerGroup();

    locations.forEach(location => {
      const [lat, lon] = location.coordinates;

      // Create custom search result marker
      const marker = L.circleMarker([lat, lon], {
        radius: 8,
        fillColor: '#ff6b35',
        color: '#ffffff',
        weight: 2,
        opacity: 1,
        fillOpacity: 0.8
      });

      // Add popup with location info
      const popupContent = `
        <div class="text-sm">
          <div class="font-semibold">${this.escapeHtml(location.place_name)}</div>
          <div class="text-gray-600 mt-1">${this.escapeHtml(location.address || '')}</div>
          <div class="mt-2">
            <span class="text-blue-600">${location.total_visits} visit(s)</span>
          </div>
        </div>
      `;

      marker.bindPopup(popupContent);
      this.searchMarkersLayer.addLayer(marker);
    });

    this.searchMarkersLayer.addTo(this.map);
  }

  focusOnLocation(location) {
    const [lat, lon] = location.coordinates;
    this.map.setView([lat, lon], 16);

    // Flash the marker
    const markers = this.searchMarkersLayer.getLayers();
    const targetMarker = markers.find(marker => {
      const latLng = marker.getLatLng();
      return Math.abs(latLng.lat - lat) < 0.0001 && Math.abs(latLng.lng - lon) < 0.0001;
    });

    if (targetMarker) {
      targetMarker.openPopup();
    }

    this.hideResults();
  }

  focusOnVisit(location, visitIndex) {
    const visit = location.visits[visitIndex];
    if (!visit) return;

    // Navigate to the visit coordinates (more precise than location coordinates)
    const [lat, lon] = visit.coordinates || location.coordinates;
    this.map.setView([lat, lon], 18); // Higher zoom for individual visit

    // Parse the visit timestamp to create a time filter
    const visitDate = new Date(visit.date);
    const startTime = new Date(visitDate.getTime() - (2 * 60 * 60 * 1000)); // 2 hours before
    const endTime = new Date(visitDate.getTime() + (2 * 60 * 60 * 1000));   // 2 hours after

    // Emit custom event for time filtering that other parts of the app can listen to
    const timeFilterEvent = new CustomEvent('locationSearch:timeFilter', {
      detail: {
        startTime: startTime.toISOString(),
        endTime: endTime.toISOString(),
        visitDate: visit.date,
        location: location.place_name,
        coordinates: [lat, lon]
      }
    });
    
    document.dispatchEvent(timeFilterEvent);

    // Create a special marker for the specific visit
    this.addVisitMarker(lat, lon, visit, location);

    // Show visit details in a popup or notification
    this.showVisitDetails(visit, location);

    // DON'T hide results - keep sidebar open
    // this.hideResults();
  }

  addVisitMarker(lat, lon, visit, location) {
    // Remove existing visit marker if any
    if (this.visitMarker) {
      this.map.removeLayer(this.visitMarker);
    }

    // Create a highlighted marker for the specific visit
    this.visitMarker = L.circleMarker([lat, lon], {
      radius: 12,
      fillColor: '#22c55e', // Green color to distinguish from search results
      color: '#ffffff',
      weight: 3,
      opacity: 1,
      fillOpacity: 0.9
    });

    const popupContent = `
      <div class="text-sm">
        <div class="font-semibold text-green-600">${this.escapeHtml(location.place_name)}</div>
        <div class="text-gray-600 mt-1">${this.escapeHtml(location.address || '')}</div>
        <div class="mt-2">
          <div class="text-xs text-gray-500">Visit Details:</div>
          <div class="text-sm">${this.formatDateTime(visit.date)}</div>
          <div class="text-xs text-gray-500">Duration: ${visit.duration_estimate}</div>
        </div>
        <div class="mt-3 pt-2 border-t border-gray-200">
          <button onclick="this.getRootNode().host?.closePopup?.() || this.closest('.leaflet-popup').querySelector('.leaflet-popup-close-button')?.click()" 
                  class="text-xs text-blue-600 hover:text-blue-800">
            Close
          </button>
        </div>
      </div>
    `;

    this.visitMarker.bindPopup(popupContent, {
      closeButton: true,
      autoClose: false, // Don't auto-close when clicking elsewhere
      closeOnEscapeKey: true, // Allow closing with Escape key
      closeOnClick: false // Don't close when clicking on map
    });
    
    this.visitMarker.addTo(this.map);
    this.visitMarker.openPopup();

    // Add event listener to clean up when popup is closed
    this.visitMarker.on('popupclose', () => {
      if (this.visitMarker) {
        this.map.removeLayer(this.visitMarker);
        this.visitMarker = null;
      }
    });

    // Store reference for manual cleanup if needed
    this.currentVisitMarker = this.visitMarker;
  }

  showVisitDetails(visit, location) {
    // Remove any existing notification
    const existingNotification = document.querySelector('.visit-navigation-notification');
    if (existingNotification) {
      existingNotification.remove();
    }

    // Create a persistent notification showing visit details
    const notification = document.createElement('div');
    notification.className = 'visit-navigation-notification fixed top-4 right-4 z-40 bg-green-50 border border-green-200 rounded-lg p-4 shadow-lg max-w-sm';
    notification.innerHTML = `
      <div class="flex items-start">
        <div class="flex-shrink-0">
          <div class="w-6 h-6 bg-green-100 rounded-full flex items-center justify-center">
            📍
          </div>
        </div>
        <div class="ml-3 flex-1">
          <div class="text-sm font-medium text-green-800">
            Viewing visit
          </div>
          <div class="text-sm text-green-600 mt-1">
            ${this.escapeHtml(location.place_name)}
          </div>
          <div class="text-xs text-green-500 mt-1">
            ${this.formatDateTime(visit.date)} • ${visit.duration_estimate}
          </div>
        </div>
        <button class="flex-shrink-0 ml-3 text-green-400 hover:text-green-500" onclick="this.parentElement.parentElement.remove()">
          ✕
        </button>
      </div>
    `;

    document.body.appendChild(notification);

    // Auto-remove notification after 10 seconds (longer duration)
    setTimeout(() => {
      if (notification.parentNode) {
        notification.remove();
      }
    }, 10000);
  }

  clearSearch() {
    this.searchInput.value = '';
    this.hideResults();
    this.clearSearchMarkers();
    this.clearVisitMarker();
    this.currentSearchQuery = '';
  }

  clearVisitMarker() {
    if (this.visitMarker) {
      this.map.removeLayer(this.visitMarker);
      this.visitMarker = null;
    }
    if (this.currentVisitMarker) {
      this.map.removeLayer(this.currentVisitMarker);
      this.currentVisitMarker = null;
    }
    
    // Remove any visit notifications
    const existingNotification = document.querySelector('.visit-navigation-notification');
    if (existingNotification) {
      existingNotification.remove();
    }
  }

  showSearchBar() {
    console.log('showSearchBar called');
    console.log('Search bar element:', this.searchBar);
    
    if (!this.searchBar) {
      console.error('Search bar element not found!');
      return;
    }
    
    // Position the search bar next to the search button
    const buttonRect = this.toggleButton.getBoundingClientRect();
    const mapRect = this.map.getContainer().getBoundingClientRect();
    
    // Position relative to the map container with more space and higher z-index
    const left = buttonRect.right - mapRect.left + 15; // Increase gap to 15px
    const top = buttonRect.top - mapRect.top;
    
    console.log('Positioning search bar at:', { left, top });
    
    // Temporarily use center position for testing
    this.searchBar.style.left = '50%';
    this.searchBar.style.top = '50%';
    this.searchBar.style.transform = 'translate(-50%, -50%)';
    this.searchBar.style.position = 'fixed';
    
    // Show the search bar - try different approaches
    this.searchBar.style.setProperty('display', 'block', 'important');
    this.searchBar.style.visibility = 'visible';
    this.searchBar.style.opacity = '1';
    this.searchVisible = true;
    
    console.log('Search bar should now be visible');
    console.log('Search bar display style after setting:', this.searchBar.style.display);
    console.log('Search bar computed style:', window.getComputedStyle(this.searchBar).display);
    console.log('Search bar HTML after showing:', this.searchBar.outerHTML);

    // Focus the search input for immediate typing
    setTimeout(() => {
      if (this.searchInput) {
        this.searchInput.focus();
      }
    }, 100);
  }

  hideSearchBar() {
    this.searchBar.style.display = 'none';
    this.searchVisible = false;
    this.clearSearch();
    this.hideResults();
    this.hideSuggestions();
  }

  showDefaultState() {
    // No default panel in inline mode, just hide suggestions and results
    this.hideSuggestions();
    this.hideResults();
  }

  clearSearchMarkers() {
    if (this.searchMarkersLayer) {
      this.map.removeLayer(this.searchMarkersLayer);
      this.searchMarkersLayer = null;
    }
  }

  hideResults() {
    if (this.resultsPanel) {
      this.resultsPanel.classList.add('hidden');
    }
  }

  // Suggestion-related methods
  debouncedSuggestionSearch(query) {
    // Clear existing timeout
    if (this.searchTimeout) {
      clearTimeout(this.searchTimeout);
    }

    // Set new timeout for debounced search
    this.searchTimeout = setTimeout(() => {
      this.performSuggestionSearch(query);
    }, 300); // 300ms debounce delay
  }

  async performSuggestionSearch(query) {
    if (query.length < 2) {
      this.hideSuggestions();
      return;
    }

    // Show loading state for suggestions
    this.showSuggestionsLoading();

    try {
      const response = await fetch(`/api/v1/locations/suggestions?q=${encodeURIComponent(query)}`, {
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json'
        }
      });

      if (!response.ok) {
        throw new Error(`Suggestions failed: ${response.status}`);
      }

      const data = await response.json();
      this.displaySuggestions(data.suggestions || []);

    } catch (error) {
      console.error('Suggestion search error:', error);
      this.hideSuggestions();
    }
  }

  showSuggestionsLoading() {
    // Hide other panels and show suggestions with loading
    this.resultsPanel.classList.add('hidden');
    this.suggestionsPanel.classList.remove('hidden');

    this.suggestionsContainer.innerHTML = `
      <div class="p-6 text-center">
        <div class="text-2xl animate-bounce">⏳</div>
        <div class="text-sm text-gray-500 mt-2">Finding suggestions...</div>
      </div>
    `;
  }

  displaySuggestions(suggestions) {
    if (!suggestions.length) {
      this.hideSuggestions();
      return;
    }

    // Hide other panels and show suggestions
    this.resultsPanel.classList.add('hidden');
    this.suggestionsPanel.classList.remove('hidden');

    // Build suggestions HTML
    let suggestionsHtml = '';
    suggestions.forEach((suggestion, index) => {
      const isActive = index === this.currentSuggestionIndex;
      suggestionsHtml += `
        <div class="suggestion-item p-4 border-b border-gray-100 hover:bg-blue-50 cursor-pointer ${isActive ? 'bg-blue-50 text-blue-700' : ''}" 
             data-suggestion-index="${index}">
          <div class="font-medium text-sm">${this.escapeHtml(suggestion.name)}</div>
          <div class="text-xs text-gray-500 mt-1">${this.escapeHtml(suggestion.address || '')}</div>
          <div class="text-xs text-gray-400 mt-1">${suggestion.type}</div>
        </div>
      `;
    });

    this.suggestionsContainer.innerHTML = suggestionsHtml;
    this.suggestionsVisible = true;
    this.suggestions = suggestions;

    // Bind click events to suggestions
    this.bindSuggestionEvents();
  }

  bindSuggestionEvents() {
    const suggestionItems = this.suggestionsContainer.querySelectorAll('.suggestion-item');
    suggestionItems.forEach(item => {
      item.addEventListener('click', (e) => {
        const index = parseInt(e.currentTarget.dataset.suggestionIndex);
        this.selectSuggestion(index);
      });
    });
  }

  navigateSuggestions(direction) {
    if (!this.suggestions || !this.suggestions.length) return;

    const maxIndex = this.suggestions.length - 1;
    
    if (direction > 0) {
      // Arrow down
      this.currentSuggestionIndex = this.currentSuggestionIndex < maxIndex 
        ? this.currentSuggestionIndex + 1 
        : 0;
    } else {
      // Arrow up
      this.currentSuggestionIndex = this.currentSuggestionIndex > 0 
        ? this.currentSuggestionIndex - 1 
        : maxIndex;
    }

    this.highlightActiveSuggestion();
  }

  highlightActiveSuggestion() {
    const suggestionItems = this.suggestionsContainer.querySelectorAll('.suggestion-item');
    
    suggestionItems.forEach((item, index) => {
      if (index === this.currentSuggestionIndex) {
        item.classList.add('bg-blue-50', 'text-blue-700');
        item.classList.remove('bg-gray-50');
      } else {
        item.classList.remove('bg-blue-50', 'text-blue-700');
        item.classList.add('bg-gray-50');
      }
    });
  }

  selectSuggestion(index) {
    if (!this.suggestions || index < 0 || index >= this.suggestions.length) return;

    const suggestion = this.suggestions[index];
    this.searchInput.value = suggestion.name;
    this.hideSuggestions();
    this.showSearchLoading(suggestion.name);
    this.performCoordinateSearch(suggestion); // Use coordinate-based search for selected suggestion
  }

  showSearchLoading(locationName) {
    // Hide other panels and show loading for search results
    this.suggestionsPanel.classList.add('hidden');
    this.resultsPanel.classList.remove('hidden');

    this.resultsContainer.innerHTML = `
      <div class="p-8 text-center">
        <div class="text-3xl animate-bounce">⏳</div>
        <div class="text-sm text-gray-600 mt-3">Searching visits to</div>
        <div class="text-sm font-medium text-gray-800">${this.escapeHtml(locationName)}</div>
      </div>
    `;
  }

  async performCoordinateSearch(suggestion) {
    this.currentSearchQuery = suggestion.name;
    // Loading state already shown by showSearchLoading

    try {
      const params = new URLSearchParams({
        lat: suggestion.coordinates[0],
        lon: suggestion.coordinates[1],
        name: suggestion.name,
        address: suggestion.address || ''
      });

      const response = await fetch(`/api/v1/locations?${params}`, {
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json'
        }
      });

      if (!response.ok) {
        throw new Error(`Coordinate search failed: ${response.status} ${response.statusText}`);
      }

      const data = await response.json();
      this.displaySearchResults(data);

    } catch (error) {
      console.error('Coordinate search error:', error);
      this.showError('Failed to search locations. Please try again.');
    }
  }

  hideSuggestions() {
    this.suggestionsPanel.classList.add('hidden');
    this.suggestionsVisible = false;
    this.currentSuggestionIndex = -1;
    this.suggestions = [];
    
    if (this.searchTimeout) {
      clearTimeout(this.searchTimeout);
      this.searchTimeout = null;
    }
  }

  // Utility methods
  escapeHtml(text) {
    const map = {
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#039;'
    };
    return text ? text.replace(/[&<>"']/g, m => map[m]) : '';
  }

  formatDate(dateString) {
    return new Date(dateString).toLocaleDateString();
  }

  formatDateTime(dateString) {
    return new Date(dateString).toLocaleDateString() + ' ' +
           new Date(dateString).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'});
  }
}

export { LocationSearch };
