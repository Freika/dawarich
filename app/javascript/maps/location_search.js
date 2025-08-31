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
    this.initializeSearchResults();
    this.initializeSuggestions();
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
    this.map.addControl(new SearchToggleControl({ position: 'topright' }));

    // Get reference to the created button
    const toggleButton = document.getElementById('location-search-toggle');

    // Create search container (initially hidden)
    // Position it to the left of the search toggle button using fixed positioning
    const searchContainer = document.createElement('div');
    searchContainer.className = 'location-search-container fixed z-50 w-80 hidden bg-white rounded-lg shadow-xl border p-2';
    searchContainer.id = 'location-search-container';

    // Create search input
    const searchInput = document.createElement('input');
    searchInput.type = 'text';
    searchInput.placeholder = 'Search locations';
    searchInput.className = 'input input-bordered w-full text-sm bg-white shadow-lg';
    searchInput.id = 'location-search-input';

    // Create search button
    const searchButton = document.createElement('button');
    searchButton.innerHTML = '🔍';
    searchButton.className = 'btn btn-primary btn-sm absolute right-2 top-1/2 transform -translate-y-1/2';
    searchButton.type = 'button';

    // Create clear button
    const clearButton = document.createElement('button');
    clearButton.innerHTML = '✕';
    clearButton.className = 'btn btn-ghost btn-xs absolute right-12 top-1/2 transform -translate-y-1/2 hidden';
    clearButton.id = 'location-search-clear';

    // Assemble search bar
    const searchWrapper = document.createElement('div');
    searchWrapper.className = 'relative';
    searchWrapper.appendChild(searchInput);
    searchWrapper.appendChild(clearButton);
    searchWrapper.appendChild(searchButton);

    searchContainer.appendChild(searchWrapper);

    // Add search container to map container
    const mapContainer = document.getElementById('map');
    mapContainer.appendChild(searchContainer);

    // Store references
    this.toggleButton = toggleButton;
    this.searchContainer = searchContainer;
    this.searchInput = searchInput;
    this.searchButton = searchButton;
    this.clearButton = clearButton;
    this.searchVisible = false;

    // Bind events
    this.bindSearchEvents();
  }

  initializeSearchResults() {
    // Create results container (positioned below search container)
    const resultsContainer = document.createElement('div');
    resultsContainer.className = 'location-search-results fixed z-40 w-80 max-h-96 overflow-y-auto bg-white rounded-lg shadow-xl border hidden';
    resultsContainer.id = 'location-search-results';

    const mapContainer = document.getElementById('map');
    mapContainer.appendChild(resultsContainer);

    this.resultsContainer = resultsContainer;
  }

  initializeSuggestions() {
    // Create suggestions dropdown (positioned below search input)
    const suggestionsContainer = document.createElement('div');
    suggestionsContainer.className = 'location-search-suggestions fixed z-50 w-80 max-h-48 overflow-y-auto bg-white rounded-lg shadow-xl border hidden';
    suggestionsContainer.id = 'location-search-suggestions';

    const mapContainer = document.getElementById('map');
    mapContainer.appendChild(suggestionsContainer);

    this.suggestionsContainer = suggestionsContainer;
  }

  bindSearchEvents() {
    // Toggle search bar visibility
    this.toggleButton.addEventListener('click', () => {
      this.toggleSearchBar();
    });

    // Search on button click
    this.searchButton.addEventListener('click', () => {
      this.performSearch();
    });

    // Search on Enter key
    this.searchInput.addEventListener('keypress', (e) => {
      if (e.key === 'Enter') {
        this.performSearch();
      }
    });

    // Clear search
    this.clearButton.addEventListener('click', () => {
      this.clearSearch();
    });

    // Show clear button when input has content and handle real-time suggestions
    this.searchInput.addEventListener('input', (e) => {
      const query = e.target.value.trim();
      
      if (query.length > 0) {
        this.clearButton.classList.remove('hidden');
        this.debouncedSuggestionSearch(query);
      } else {
        this.clearButton.classList.add('hidden');
        this.hideSuggestions();
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
          case 'Enter':
            e.preventDefault();
            if (this.currentSuggestionIndex >= 0) {
              this.selectSuggestion(this.currentSuggestionIndex);
            } else {
              this.performSearch();
            }
            break;
          case 'Escape':
            this.hideSuggestions();
            break;
        }
      }
    });

    // Hide results and search bar when clicking outside
    document.addEventListener('click', (e) => {
      if (!e.target.closest('.location-search-container') &&
          !e.target.closest('.location-search-results') &&
          !e.target.closest('.location-search-suggestions') &&
          !e.target.closest('#location-search-toggle')) {
        this.hideResults();
        this.hideSuggestions();
        if (this.searchVisible) {
          this.hideSearchBar();
        }
      }
    });

    // Close search bar on Escape key
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && this.searchVisible) {
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
    this.resultsContainer.innerHTML = `
      <div class="p-4 text-center">
        <div class="loading loading-spinner loading-sm"></div>
        <div class="text-sm text-gray-600 mt-2">Searching for "${this.currentSearchQuery}"...</div>
      </div>
    `;
    this.resultsContainer.classList.remove('hidden');
  }

  showError(message) {
    // Position results container below search container using viewport coordinates
    const searchRect = this.searchContainer.getBoundingClientRect();

    const resultsTop = searchRect.bottom + 5;
    const resultsRight = window.innerWidth - searchRect.left;

    this.resultsContainer.style.top = resultsTop + 'px';
    this.resultsContainer.style.right = resultsRight + 'px';

    this.resultsContainer.innerHTML = `
      <div class="p-4 text-center">
        <div class="text-error text-sm">${message}</div>
      </div>
    `;
    this.resultsContainer.classList.remove('hidden');
  }

  displaySearchResults(data) {
    // Position results container below search container using viewport coordinates
    const searchRect = this.searchContainer.getBoundingClientRect();

    const resultsTop = searchRect.bottom + 5; // 5px gap below search container
    const resultsRight = window.innerWidth - searchRect.left; // Align with left edge of search container

    this.resultsContainer.style.top = resultsTop + 'px';
    this.resultsContainer.style.right = resultsRight + 'px';

    if (!data.locations || data.locations.length === 0) {
      this.resultsContainer.innerHTML = `
        <div class="p-4 text-center">
          <div class="text-sm text-gray-600">No visits found for "${this.currentSearchQuery}"</div>
        </div>
      `;
      this.resultsContainer.classList.remove('hidden');
      return;
    }

    this.searchResults = data.locations;
    this.clearSearchMarkers();

    let resultsHtml = `
      <div class="p-3 border-b">
        <div class="text-sm font-semibold">Found ${data.total_locations} location(s) for "${this.currentSearchQuery}"</div>
      </div>
    `;

    data.locations.forEach((location, index) => {
      resultsHtml += this.buildLocationResultHtml(location, index);
    });

    this.resultsContainer.innerHTML = resultsHtml;
    this.resultsContainer.classList.remove('hidden');

    // Add markers to map
    this.addSearchMarkersToMap(data.locations);

    // Bind result interaction events
    this.bindResultEvents();
  }

  buildLocationResultHtml(location, index) {
    const firstVisit = location.visits[0];
    const lastVisit = location.visits[location.visits.length - 1];

    return `
      <div class="location-result p-3 border-b hover:bg-gray-50 cursor-pointer" data-location-index="${index}">
        <div class="font-medium text-sm">${this.escapeHtml(location.place_name)}</div>
        <div class="text-xs text-gray-600 mt-1">${this.escapeHtml(location.address || '')}</div>
        <div class="flex justify-between items-center mt-2">
          <div class="text-xs text-blue-600">${location.total_visits} visit(s)</div>
          <div class="text-xs text-gray-500">
            ${this.formatDate(firstVisit.date)} - ${this.formatDate(lastVisit.date)}
          </div>
        </div>
        <div class="mt-2 max-h-32 overflow-y-auto">
          ${location.visits.slice(0, 5).map(visit => `
            <div class="text-xs text-gray-700 py-1 border-t border-gray-100 first:border-t-0">
              📍 ${this.formatDateTime(visit.date)} (${visit.distance_meters}m away)
            </div>
          `).join('')}
          ${location.visits.length > 5 ? `<div class="text-xs text-gray-500 mt-1">+ ${location.visits.length - 5} more visits</div>` : ''}
        </div>
      </div>
    `;
  }

  bindResultEvents() {
    const locationResults = this.resultsContainer.querySelectorAll('.location-result');
    locationResults.forEach(result => {
      result.addEventListener('click', (e) => {
        const index = parseInt(e.currentTarget.dataset.locationIndex);
        this.focusOnLocation(this.searchResults[index]);
      });
    });
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

  clearSearch() {
    this.searchInput.value = '';
    this.clearButton.classList.add('hidden');
    this.hideResults();
    this.clearSearchMarkers();
    this.currentSearchQuery = '';
  }

  toggleSearchBar() {
    if (this.searchVisible) {
      this.hideSearchBar();
    } else {
      this.showSearchBar();
    }
  }

  showSearchBar() {
    // Calculate position relative to the toggle button using viewport coordinates
    const buttonRect = this.toggleButton.getBoundingClientRect();

    // Position search container to the left of the button, aligned vertically
    // Using fixed positioning relative to viewport
    const searchTop = buttonRect.top; // Same vertical position as button (viewport coordinates)
    const searchRight = window.innerWidth - buttonRect.left + 10; // 10px gap to the left of button

    // Debug logging to see actual values
    console.log('Button rect:', buttonRect);
    console.log('Window width:', window.innerWidth);
    console.log('Calculated top:', searchTop);
    console.log('Calculated right:', searchRight);

    this.searchContainer.style.top = searchTop + 'px';
    this.searchContainer.style.right = searchRight + 'px';

    this.searchContainer.classList.remove('hidden');
    this.searchVisible = true;

    // Focus the search input for immediate typing
    setTimeout(() => {
      this.searchInput.focus();
    }, 100);
  }

  hideSearchBar() {
    this.searchContainer.classList.add('hidden');
    this.hideResults();
    this.clearSearch();
    this.searchVisible = false;
  }

  clearSearchMarkers() {
    if (this.searchMarkersLayer) {
      this.map.removeLayer(this.searchMarkersLayer);
      this.searchMarkersLayer = null;
    }
  }

  hideResults() {
    this.resultsContainer.classList.add('hidden');
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

  displaySuggestions(suggestions) {
    if (!suggestions.length) {
      this.hideSuggestions();
      return;
    }

    // Position suggestions container below search input, aligned with the search container
    const searchRect = this.searchContainer.getBoundingClientRect();
    const suggestionsTop = searchRect.bottom + 2;
    const suggestionsRight = window.innerWidth - searchRect.left;

    this.suggestionsContainer.style.top = suggestionsTop + 'px';
    this.suggestionsContainer.style.right = suggestionsRight + 'px';

    // Build suggestions HTML
    let suggestionsHtml = '';
    suggestions.forEach((suggestion, index) => {
      const isActive = index === this.currentSuggestionIndex;
      suggestionsHtml += `
        <div class="suggestion-item p-2 border-b border-gray-100 hover:bg-gray-50 cursor-pointer text-sm ${isActive ? 'bg-blue-50 text-blue-700' : ''}" 
             data-suggestion-index="${index}">
          <div class="font-medium">${this.escapeHtml(suggestion.name)}</div>
          <div class="text-xs text-gray-600">${this.escapeHtml(suggestion.address || '')}</div>
        </div>
      `;
    });

    this.suggestionsContainer.innerHTML = suggestionsHtml;
    this.suggestionsContainer.classList.remove('hidden');
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
    this.performCoordinateSearch(suggestion); // Use coordinate-based search for selected suggestion
  }

  async performCoordinateSearch(suggestion) {
    this.currentSearchQuery = suggestion.name;
    this.showLoading();

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
    this.suggestionsContainer.classList.add('hidden');
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
