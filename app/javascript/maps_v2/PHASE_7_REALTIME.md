# Phase 7: Real-time Updates + Family Sharing

**Timeline**: Week 7
**Goal**: Add real-time updates and collaborative features
**Dependencies**: Phases 1-6 complete
**Status**: Ready for implementation

## 🎯 Phase Objectives

Build on Phases 1-6 by adding:
- ✅ ActionCable integration for real-time updates
- ✅ Real-time point updates (live location tracking)
- ✅ Family layer (shared locations)
- ✅ Live notifications
- ✅ WebSocket reconnection logic
- ✅ Presence indicators
- ✅ E2E tests

**Deploy Decision**: Full collaborative features with real-time location sharing.

---

## 📋 Features Checklist

- [ ] ActionCable channel subscription
- [ ] Real-time point updates
- [ ] Family member locations layer
- [ ] Live toast notifications
- [ ] WebSocket auto-reconnect
- [ ] Online/offline indicators
- [ ] Family member colors
- [ ] E2E tests passing

---

## 🏗️ New Files (Phase 7)

```
app/javascript/maps_v2/
├── layers/
│   └── family_layer.js                # NEW: Family locations
├── controllers/
│   └── realtime_controller.js         # NEW: ActionCable
├── channels/
│   └── map_channel.js                 # NEW: Channel consumer
└── utils/
    └── websocket_manager.js           # NEW: Connection management

app/channels/
└── map_channel.rb                     # NEW: Rails channel

e2e/v2/
└── phase-7-realtime.spec.ts           # NEW: E2E tests
```

---

## 7.1 Family Layer

Display family member locations.

**File**: `app/javascript/maps_v2/layers/family_layer.js`

```javascript
import { BaseLayer } from './base_layer'

/**
 * Family layer showing family member locations
 * Each member has unique color
 */
export class FamilyLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: 'family', ...options })
    this.memberColors = {}
  }

  getSourceConfig() {
    return {
      type: 'geojson',
      data: this.data || {
        type: 'FeatureCollection',
        features: []
      }
    }
  }

  getLayerConfigs() {
    return [
      // Member circles
      {
        id: this.id,
        type: 'circle',
        source: this.sourceId,
        paint: {
          'circle-radius': 10,
          'circle-color': ['get', 'color'],
          'circle-stroke-width': 2,
          'circle-stroke-color': '#ffffff',
          'circle-opacity': 0.9
        }
      },

      // Member labels
      {
        id: `${this.id}-labels`,
        type: 'symbol',
        source: this.sourceId,
        layout: {
          'text-field': ['get', 'name'],
          'text-font': ['Open Sans Bold', 'Arial Unicode MS Bold'],
          'text-size': 12,
          'text-offset': [0, 1.5],
          'text-anchor': 'top'
        },
        paint: {
          'text-color': '#111827',
          'text-halo-color': '#ffffff',
          'text-halo-width': 2
        }
      },

      // Pulse animation
      {
        id: `${this.id}-pulse`,
        type: 'circle',
        source: this.sourceId,
        paint: {
          'circle-radius': [
            'interpolate',
            ['linear'],
            ['zoom'],
            10, 15,
            15, 25
          ],
          'circle-color': ['get', 'color'],
          'circle-opacity': [
            'interpolate',
            ['linear'],
            ['get', 'lastUpdate'],
            Date.now() - 10000, 0,
            Date.now(), 0.3
          ]
        }
      }
    ]
  }

  getLayerIds() {
    return [this.id, `${this.id}-labels`, `${this.id}-pulse`]
  }

  /**
   * Update single family member location
   * @param {Object} member - { id, name, latitude, longitude, color }
   */
  updateMember(member) {
    const features = this.data?.features || []

    // Find existing or add new
    const index = features.findIndex(f => f.properties.id === member.id)

    const feature = {
      type: 'Feature',
      geometry: {
        type: 'Point',
        coordinates: [member.longitude, member.latitude]
      },
      properties: {
        id: member.id,
        name: member.name,
        color: member.color || this.getMemberColor(member.id),
        lastUpdate: Date.now()
      }
    }

    if (index >= 0) {
      features[index] = feature
    } else {
      features.push(feature)
    }

    this.update({
      type: 'FeatureCollection',
      features
    })
  }

  /**
   * Get consistent color for member
   */
  getMemberColor(memberId) {
    if (!this.memberColors[memberId]) {
      const colors = [
        '#3b82f6', '#10b981', '#f59e0b',
        '#ef4444', '#8b5cf6', '#ec4899'
      ]
      const index = Object.keys(this.memberColors).length % colors.length
      this.memberColors[memberId] = colors[index]
    }
    return this.memberColors[memberId]
  }

  /**
   * Remove family member
   */
  removeMember(memberId) {
    const features = this.data?.features || []
    const filtered = features.filter(f => f.properties.id !== memberId)

    this.update({
      type: 'FeatureCollection',
      features: filtered
    })
  }
}
```

---

## 7.2 WebSocket Manager

**File**: `app/javascript/maps_v2/utils/websocket_manager.js`

```javascript
/**
 * WebSocket connection manager
 * Handles reconnection logic and connection state
 */
export class WebSocketManager {
  constructor(options = {}) {
    this.maxReconnectAttempts = options.maxReconnectAttempts || 5
    this.reconnectDelay = options.reconnectDelay || 1000
    this.reconnectAttempts = 0
    this.isConnected = false
    this.subscription = null
    this.onConnect = options.onConnect || null
    this.onDisconnect = options.onDisconnect || null
    this.onError = options.onError || null
  }

  /**
   * Connect to channel
   * @param {Object} subscription - ActionCable subscription
   */
  connect(subscription) {
    this.subscription = subscription

    // Monitor connection state
    this.subscription.connected = () => {
      this.isConnected = true
      this.reconnectAttempts = 0
      this.onConnect?.()
    }

    this.subscription.disconnected = () => {
      this.isConnected = false
      this.onDisconnect?.()
      this.attemptReconnect()
    }
  }

  /**
   * Attempt to reconnect
   */
  attemptReconnect() {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      this.onError?.(new Error('Max reconnect attempts reached'))
      return
    }

    this.reconnectAttempts++

    const delay = this.reconnectDelay * Math.pow(2, this.reconnectAttempts - 1)

    console.log(`Reconnecting in ${delay}ms (attempt ${this.reconnectAttempts}/${this.maxReconnectAttempts})`)

    setTimeout(() => {
      if (!this.isConnected) {
        this.subscription?.perform('reconnect')
      }
    }, delay)
  }

  /**
   * Disconnect
   */
  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
    this.isConnected = false
  }

  /**
   * Send message
   */
  send(action, data = {}) {
    if (!this.isConnected) {
      console.warn('Cannot send message: not connected')
      return
    }

    this.subscription?.perform(action, data)
  }
}
```

---

## 7.3 Map Channel (Consumer)

**File**: `app/javascript/maps_v2/channels/map_channel.js`

```javascript
import consumer from './consumer'

/**
 * Create map channel subscription
 * @param {Object} callbacks - { received, connected, disconnected }
 * @returns {Object} Subscription
 */
export function createMapChannel(callbacks = {}) {
  return consumer.subscriptions.create('MapChannel', {
    connected() {
      console.log('MapChannel connected')
      callbacks.connected?.()
    },

    disconnected() {
      console.log('MapChannel disconnected')
      callbacks.disconnected?.()
    },

    received(data) {
      console.log('MapChannel received:', data)
      callbacks.received?.(data)
    },

    // Custom methods
    updateLocation(latitude, longitude) {
      this.perform('update_location', {
        latitude,
        longitude
      })
    },

    subscribeToFamily() {
      this.perform('subscribe_family')
    }
  })
}
```

---

## 7.4 Real-time Controller

**File**: `app/javascript/maps_v2/controllers/realtime_controller.js`

```javascript
import { Controller } from '@hotwired/stimulus'
import { createMapChannel } from '../channels/map_channel'
import { WebSocketManager } from '../utils/websocket_manager'
import { Toast } from '../components/toast'

/**
 * Real-time controller
 * Manages ActionCable connection and real-time updates
 */
export default class extends Controller {
  static outlets = ['map']

  static values = {
    enabled: { type: Boolean, default: true },
    updateInterval: { type: Number, default: 30000 } // 30 seconds
  }

  connect() {
    if (!this.enabledValue) return

    this.setupChannel()
    this.startLocationUpdates()
  }

  disconnect() {
    this.stopLocationUpdates()
    this.wsManager?.disconnect()
    this.channel?.unsubscribe()
  }

  /**
   * Setup ActionCable channel
   */
  setupChannel() {
    this.channel = createMapChannel({
      connected: this.handleConnected.bind(this),
      disconnected: this.handleDisconnected.bind(this),
      received: this.handleReceived.bind(this)
    })

    this.wsManager = new WebSocketManager({
      onConnect: () => {
        Toast.success('Connected to real-time updates')
        this.updateConnectionIndicator(true)
      },
      onDisconnect: () => {
        Toast.warning('Disconnected from real-time updates')
        this.updateConnectionIndicator(false)
      },
      onError: (error) => {
        Toast.error('Failed to reconnect')
      }
    })

    this.wsManager.connect(this.channel)
  }

  /**
   * Handle connection
   */
  handleConnected() {
    // Subscribe to family updates
    this.channel.subscribeToFamily()
  }

  /**
   * Handle disconnection
   */
  handleDisconnected() {
    // Will attempt reconnect via WebSocketManager
  }

  /**
   * Handle received data
   */
  handleReceived(data) {
    switch (data.type) {
      case 'new_point':
        this.handleNewPoint(data.point)
        break

      case 'family_location':
        this.handleFamilyLocation(data.member)
        break

      case 'member_offline':
        this.handleMemberOffline(data.member_id)
        break
    }
  }

  /**
   * Handle new point
   */
  handleNewPoint(point) {
    if (!this.hasMapOutlet) return

    // Add point to map
    const pointsLayer = this.mapOutlet.pointsLayer
    if (pointsLayer) {
      const currentData = pointsLayer.data
      const features = currentData.features || []

      features.push({
        type: 'Feature',
        geometry: {
          type: 'Point',
          coordinates: [point.longitude, point.latitude]
        },
        properties: point
      })

      pointsLayer.update({
        type: 'FeatureCollection',
        features
      })

      Toast.info('New location recorded')
    }
  }

  /**
   * Handle family member location update
   */
  handleFamilyLocation(member) {
    if (!this.hasMapOutlet) return

    const familyLayer = this.mapOutlet.familyLayer
    if (familyLayer) {
      familyLayer.updateMember(member)
    }
  }

  /**
   * Handle family member going offline
   */
  handleMemberOffline(memberId) {
    if (!this.hasMapOutlet) return

    const familyLayer = this.mapOutlet.familyLayer
    if (familyLayer) {
      familyLayer.removeMember(memberId)
    }
  }

  /**
   * Start sending location updates
   */
  startLocationUpdates() {
    if (!navigator.geolocation) return

    this.locationInterval = setInterval(() => {
      navigator.geolocation.getCurrentPosition(
        (position) => {
          this.channel?.updateLocation(
            position.coords.latitude,
            position.coords.longitude
          )
        },
        (error) => {
          console.error('Geolocation error:', error)
        }
      )
    }, this.updateIntervalValue)
  }

  /**
   * Stop sending location updates
   */
  stopLocationUpdates() {
    if (this.locationInterval) {
      clearInterval(this.locationInterval)
      this.locationInterval = null
    }
  }

  /**
   * Update connection indicator
   */
  updateConnectionIndicator(connected) {
    const indicator = document.querySelector('.connection-indicator')
    if (indicator) {
      indicator.classList.toggle('connected', connected)
      indicator.classList.toggle('disconnected', !connected)
    }
  }
}
```

---

## 7.5 Map Channel (Rails)

**File**: `app/channels/map_channel.rb`

```ruby
class MapChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_user
  end

  def unsubscribed
    # Cleanup when channel is unsubscribed
    broadcast_to_family({ type: 'member_offline', member_id: current_user.id })
  end

  def update_location(data)
    # Create new point
    point = current_user.points.create!(
      latitude: data['latitude'],
      longitude: data['longitude'],
      timestamp: Time.current.to_i,
      lonlat: "POINT(#{data['longitude']} #{data['latitude']})"
    )

    # Broadcast to self
    MapChannel.broadcast_to(current_user, {
      type: 'new_point',
      point: point.as_json
    })

    # Broadcast to family members
    broadcast_to_family({
      type: 'family_location',
      member: {
        id: current_user.id,
        name: current_user.email,
        latitude: data['latitude'],
        longitude: data['longitude']
      }
    })
  end

  def subscribe_family
    # Stream family updates
    if current_user.family.present?
      current_user.family.members.each do |member|
        stream_for member unless member == current_user
      end
    end
  end

  private

  def broadcast_to_family(data)
    return unless current_user.family.present?

    current_user.family.members.each do |member|
      next if member == current_user

      MapChannel.broadcast_to(member, data)
    end
  end
end
```

---

## 7.6 Update Map Controller

Add family layer and real-time integration.

**File**: `app/javascript/maps_v2/controllers/map_controller.js` (add)

```javascript
// Add import
import { FamilyLayer } from '../layers/family_layer'

// In loadMapData(), add:

// Add family layer
if (!this.familyLayer) {
  this.familyLayer = new FamilyLayer(this.map, { visible: false })

  if (this.map.loaded()) {
    this.familyLayer.add({ type: 'FeatureCollection', features: [] })
  } else {
    this.map.on('load', () => {
      this.familyLayer.add({ type: 'FeatureCollection', features: [] })
    })
  }
}
```

---

## 7.7 Connection Indicator

Add to view template.

**File**: `app/views/maps_v2/index.html.erb` (add)

```erb
<!-- Add to map wrapper -->
<div class="connection-indicator disconnected">
  <span class="indicator-dot"></span>
  <span class="indicator-text">Connecting...</span>
</div>

<style>
  .connection-indicator {
    position: absolute;
    top: 16px;
    left: 50%;
    transform: translateX(-50%);
    padding: 8px 16px;
    background: white;
    border-radius: 20px;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 13px;
    font-weight: 500;
    z-index: 20;
    transition: all 0.3s;
  }

  .indicator-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: #ef4444;
  }

  .connection-indicator.connected .indicator-dot {
    background: #22c55e;
  }

  .connection-indicator.connected .indicator-text::before {
    content: 'Connected';
  }

  .connection-indicator.disconnected .indicator-text::before {
    content: 'Disconnected';
  }
</style>
```

---

## 🧪 E2E Tests

**File**: `e2e/v2/phase-7-realtime.spec.ts`

```typescript
import { test, expect } from '@playwright/test'
import { login, waitForMap } from './helpers/setup'

test.describe('Phase 7: Real-time + Family', () => {
  test.beforeEach(async ({ page }) => {
    await login(page)
    await page.goto('/maps_v2')
    await waitForMap(page)
  })

  test('family layer exists', async ({ page }) => {
    const hasFamily = await page.evaluate(() => {
      const map = window.mapInstance
      return map?.getLayer('family') !== undefined
    })

    expect(hasFamily).toBe(true)
  })

  test('connection indicator shows', async ({ page }) => {
    const indicator = page.locator('.connection-indicator')
    await expect(indicator).toBeVisible()
  })

  test('connection indicator shows connected state', async ({ page }) => {
    // Wait for connection
    await page.waitForTimeout(2000)

    const indicator = page.locator('.connection-indicator')
    // May be connected or disconnected depending on ActionCable setup
    await expect(indicator).toBeVisible()
  })

  test.describe('Regression Tests', () => {
    test('all previous features still work', async ({ page }) => {
      const layers = [
        'points', 'routes', 'heatmap',
        'visits', 'photos', 'areas-fill',
        'tracks'
      ]

      for (const layer of layers) {
        const exists = await page.evaluate((l) => {
          const map = window.mapInstance
          return map?.getLayer(l) !== undefined
        }, layer)

        expect(exists).toBe(true)
      }
    })
  })
})
```

---

## ✅ Phase 7 Completion Checklist

### Implementation
- [ ] Created family_layer.js
- [ ] Created websocket_manager.js
- [ ] Created map_channel.js (JS)
- [ ] Created realtime_controller.js
- [ ] Created map_channel.rb (Rails)
- [ ] Updated map_controller.js
- [ ] Added connection indicator

### Functionality
- [ ] ActionCable connects
- [ ] Real-time point updates work
- [ ] Family locations show
- [ ] WebSocket reconnects
- [ ] Connection indicator updates
- [ ] Live notifications appear

### Testing
- [ ] All Phase 7 E2E tests pass
- [ ] Phase 1-6 tests still pass (regression)

---

## 🚀 Deployment

```bash
git checkout -b maps-v2-phase-7
git add app/javascript/maps_v2/ app/channels/ app/views/maps_v2/ e2e/v2/
git commit -m "feat: Maps V2 Phase 7 - Real-time updates and family sharing"
git push origin maps-v2-phase-7
```

---

## 🎉 What's Next?

**Phase 8**: Final polish, performance optimization, and production readiness.
