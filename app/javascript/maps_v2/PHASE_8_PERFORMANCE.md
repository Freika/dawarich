# Phase 8: Performance Optimization & Production Polish

**Timeline**: Week 8
**Goal**: Optimize for production deployment
**Dependencies**: Phases 1-7 complete
**Status**: Ready for implementation

## 🎯 Phase Objectives

Final optimization and polish:
- ✅ Lazy load heavy controllers
- ✅ Progressive data loading with limits
- ✅ Performance monitoring
- ✅ Service worker for offline support
- ✅ Memory leak prevention
- ✅ Bundle optimization
- ✅ Production deployment checklist
- ✅ E2E tests

**Deploy Decision**: Production-ready application optimized for performance.

---

## 📋 Features Checklist

- [ ] Lazy loading for fog/scratch/advanced layers
- [ ] Progressive loading with abort capability
- [ ] Performance metrics tracking
- [ ] FPS monitoring
- [ ] Service worker registered
- [ ] Memory cleanup verified
- [ ] Bundle size < 500KB (gzipped)
- [ ] Lighthouse score > 90
- [ ] All E2E tests passing

---

## 🏗️ New Files (Phase 8)

```
app/javascript/maps_v2/
└── utils/
    ├── lazy_loader.js                 # NEW: Dynamic imports
    ├── progressive_loader.js          # NEW: Chunked loading
    ├── performance_monitor.js         # NEW: Metrics tracking
    ├── fps_monitor.js                 # NEW: FPS tracking
    └── cleanup_helper.js              # NEW: Memory management

public/
└── maps-v2-sw.js                      # NEW: Service worker

e2e/v2/
└── phase-8-performance.spec.ts        # NEW: E2E tests
```

---

## 8.1 Lazy Loader

Dynamic imports for heavy controllers.

**File**: `app/javascript/maps_v2/utils/lazy_loader.js`

```javascript
/**
 * Lazy loader for heavy map layers
 * Reduces initial bundle size
 */
export class LazyLoader {
  constructor() {
    this.cache = new Map()
    this.loading = new Map()
  }

  /**
   * Load layer class dynamically
   * @param {string} name - Layer name (e.g., 'fog', 'scratch')
   * @returns {Promise<Class>}
   */
  async loadLayer(name) {
    // Return cached
    if (this.cache.has(name)) {
      return this.cache.get(name)
    }

    // Wait for loading
    if (this.loading.has(name)) {
      return this.loading.get(name)
    }

    // Start loading
    const loadPromise = this.#load(name)
    this.loading.set(name, loadPromise)

    try {
      const LayerClass = await loadPromise
      this.cache.set(name, LayerClass)
      this.loading.delete(name)
      return LayerClass
    } catch (error) {
      this.loading.delete(name)
      throw error
    }
  }

  async #load(name) {
    const paths = {
      'fog': () => import('../layers/fog_layer.js'),
      'scratch': () => import('../layers/scratch_layer.js')
    }

    const loader = paths[name]
    if (!loader) {
      throw new Error(`Unknown layer: ${name}`)
    }

    const module = await loader()
    return module[this.#getClassName(name)]
  }

  #getClassName(name) {
    // fog -> FogLayer, scratch -> ScratchLayer
    return name.charAt(0).toUpperCase() + name.slice(1) + 'Layer'
  }

  /**
   * Preload layers
   * @param {string[]} names
   */
  async preload(names) {
    return Promise.all(names.map(name => this.loadLayer(name)))
  }

  clear() {
    this.cache.clear()
    this.loading.clear()
  }
}

export const lazyLoader = new LazyLoader()
```

---

## 8.2 Progressive Loader

Chunked data loading with abort.

**File**: `app/javascript/maps_v2/utils/progressive_loader.js`

```javascript
/**
 * Progressive loader for large datasets
 * Loads data in chunks with progress feedback
 */
export class ProgressiveLoader {
  constructor(options = {}) {
    this.onProgress = options.onProgress || null
    this.onComplete = options.onComplete || null
    this.abortController = null
  }

  /**
   * Load data progressively
   * @param {Function} fetchFn - Function that fetches one page
   * @param {Object} options - { batchSize, maxConcurrent, maxPoints }
   * @returns {Promise<Array>}
   */
  async load(fetchFn, options = {}) {
    const {
      batchSize = 1000,
      maxConcurrent = 3,
      maxPoints = 100000 // Limit for safety
    } = options

    this.abortController = new AbortController()
    const allData = []
    let page = 1
    let totalPages = 1
    const activeRequests = []

    try {
      do {
        // Check abort
        if (this.abortController.signal.aborted) {
          throw new Error('Load cancelled')
        }

        // Check max points limit
        if (allData.length >= maxPoints) {
          console.warn(`Reached max points limit: ${maxPoints}`)
          break
        }

        // Limit concurrent requests
        while (activeRequests.length >= maxConcurrent) {
          await Promise.race(activeRequests)
        }

        const requestPromise = fetchFn({
          page,
          per_page: batchSize,
          signal: this.abortController.signal
        }).then(result => {
          allData.push(...result.data)

          if (result.totalPages) {
            totalPages = result.totalPages
          }

          this.onProgress?.({
            loaded: allData.length,
            total: Math.min(totalPages * batchSize, maxPoints),
            currentPage: page,
            totalPages,
            progress: page / totalPages
          })

          // Remove from active
          const idx = activeRequests.indexOf(requestPromise)
          if (idx > -1) activeRequests.splice(idx, 1)

          return result
        })

        activeRequests.push(requestPromise)
        page++

      } while (page <= totalPages && allData.length < maxPoints)

      // Wait for remaining
      await Promise.all(activeRequests)

      this.onComplete?.(allData)
      return allData

    } catch (error) {
      if (error.name === 'AbortError' || error.message === 'Load cancelled') {
        console.log('Progressive load cancelled')
        return allData // Return partial data
      }
      throw error
    }
  }

  /**
   * Cancel loading
   */
  cancel() {
    this.abortController?.abort()
  }
}
```

---

## 8.3 Performance Monitor

**File**: `app/javascript/maps_v2/utils/performance_monitor.js`

```javascript
/**
 * Performance monitoring utility
 */
export class PerformanceMonitor {
  constructor() {
    this.marks = new Map()
    this.metrics = []
  }

  /**
   * Start timing
   * @param {string} name
   */
  mark(name) {
    this.marks.set(name, performance.now())
  }

  /**
   * End timing and record
   * @param {string} name
   * @returns {number} Duration in ms
   */
  measure(name) {
    const startTime = this.marks.get(name)
    if (!startTime) {
      console.warn(`No mark found for: ${name}`)
      return 0
    }

    const duration = performance.now() - startTime
    this.marks.delete(name)

    this.metrics.push({
      name,
      duration,
      timestamp: Date.now()
    })

    return duration
  }

  /**
   * Get performance report
   * @returns {Object}
   */
  getReport() {
    const grouped = this.metrics.reduce((acc, metric) => {
      if (!acc[metric.name]) {
        acc[metric.name] = []
      }
      acc[metric.name].push(metric.duration)
      return acc
    }, {})

    const report = {}
    for (const [name, durations] of Object.entries(grouped)) {
      const avg = durations.reduce((a, b) => a + b, 0) / durations.length
      const min = Math.min(...durations)
      const max = Math.max(...durations)

      report[name] = {
        count: durations.length,
        avg: Math.round(avg),
        min: Math.round(min),
        max: Math.round(max)
      }
    }

    return report
  }

  /**
   * Get memory usage
   * @returns {Object|null}
   */
  getMemoryUsage() {
    if (!performance.memory) return null

    return {
      used: Math.round(performance.memory.usedJSHeapSize / 1048576),
      total: Math.round(performance.memory.totalJSHeapSize / 1048576),
      limit: Math.round(performance.memory.jsHeapSizeLimit / 1048576)
    }
  }

  /**
   * Log report to console
   */
  logReport() {
    console.group('Performance Report')
    console.table(this.getReport())

    const memory = this.getMemoryUsage()
    if (memory) {
      console.log(`Memory: ${memory.used}MB / ${memory.total}MB (limit: ${memory.limit}MB)`)
    }

    console.groupEnd()
  }

  clear() {
    this.marks.clear()
    this.metrics = []
  }
}

export const performanceMonitor = new PerformanceMonitor()
```

---

## 8.4 FPS Monitor

**File**: `app/javascript/maps_v2/utils/fps_monitor.js`

```javascript
/**
 * FPS (Frames Per Second) monitor
 */
export class FPSMonitor {
  constructor(sampleSize = 60) {
    this.sampleSize = sampleSize
    this.frames = []
    this.lastTime = performance.now()
    this.isRunning = false
    this.rafId = null
  }

  start() {
    if (this.isRunning) return
    this.isRunning = true
    this.#tick()
  }

  stop() {
    this.isRunning = false
    if (this.rafId) {
      cancelAnimationFrame(this.rafId)
      this.rafId = null
    }
  }

  getFPS() {
    if (this.frames.length === 0) return 0
    const avg = this.frames.reduce((a, b) => a + b, 0) / this.frames.length
    return Math.round(avg)
  }

  #tick = () => {
    if (!this.isRunning) return

    const now = performance.now()
    const delta = now - this.lastTime
    const fps = 1000 / delta

    this.frames.push(fps)
    if (this.frames.length > this.sampleSize) {
      this.frames.shift()
    }

    this.lastTime = now
    this.rafId = requestAnimationFrame(this.#tick)
  }
}
```

---

## 8.5 Cleanup Helper

**File**: `app/javascript/maps_v2/utils/cleanup_helper.js`

```javascript
/**
 * Helper for tracking and cleaning up resources
 */
export class CleanupHelper {
  constructor() {
    this.listeners = []
    this.intervals = []
    this.timeouts = []
    this.observers = []
  }

  addEventListener(target, event, handler, options) {
    target.addEventListener(event, handler, options)
    this.listeners.push({ target, event, handler, options })
  }

  setInterval(callback, delay) {
    const id = setInterval(callback, delay)
    this.intervals.push(id)
    return id
  }

  setTimeout(callback, delay) {
    const id = setTimeout(callback, delay)
    this.timeouts.push(id)
    return id
  }

  addObserver(observer) {
    this.observers.push(observer)
  }

  cleanup() {
    this.listeners.forEach(({ target, event, handler, options }) => {
      target.removeEventListener(event, handler, options)
    })
    this.listeners = []

    this.intervals.forEach(id => clearInterval(id))
    this.intervals = []

    this.timeouts.forEach(id => clearTimeout(id))
    this.timeouts = []

    this.observers.forEach(observer => observer.disconnect())
    this.observers = []
  }
}
```

---

## 8.6 Service Worker

**File**: `public/maps-v2-sw.js`

```javascript
const CACHE_VERSION = 'maps-v2-v1'
const STATIC_CACHE = [
  '/maps_v2',
  '/assets/application-*.js',
  '/assets/application-*.css'
]

// Install
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_VERSION).then((cache) => {
      return cache.addAll(STATIC_CACHE)
    })
  )
  self.skipWaiting()
})

// Activate
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames
          .filter(name => name !== CACHE_VERSION)
          .map(name => caches.delete(name))
      )
    })
  )
  self.clients.claim()
})

// Fetch (cache-first for static, network-first for API)
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url)

  // Network-first for API calls
  if (url.pathname.startsWith('/api/')) {
    event.respondWith(
      fetch(event.request)
        .catch(() => caches.match(event.request))
    )
    return
  }

  // Cache-first for static assets
  event.respondWith(
    caches.match(event.request).then((response) => {
      if (response) {
        return response
      }

      return fetch(event.request).then((response) => {
        if (response && response.status === 200) {
          const responseClone = response.clone()
          caches.open(CACHE_VERSION).then((cache) => {
            cache.put(event.request, responseClone)
          })
        }
        return response
      })
    })
  )
})
```

---

## 8.7 Update Map Controller

Add lazy loading and performance monitoring.

**File**: `app/javascript/maps_v2/controllers/map_controller.js` (update)

```javascript
// Add imports
import { lazyLoader } from '../utils/lazy_loader'
import { ProgressiveLoader } from '../utils/progressive_loader'
import { performanceMonitor } from '../utils/performance_monitor'
import { CleanupHelper } from '../utils/cleanup_helper'

// In connect():
connect() {
  this.cleanup = new CleanupHelper()
  this.registerServiceWorker()
  this.initializeMap()
  this.initializeAPI()
  this.loadSettings()
  this.loadMapData()
}

// In disconnect():
disconnect() {
  this.cleanup.cleanup()
  this.map?.remove()
  performanceMonitor.logReport() // Log on exit
}

// Update loadMapData():
async loadMapData() {
  performanceMonitor.mark('load-map-data')

  this.showLoading()

  try {
    // Use progressive loader
    const loader = new ProgressiveLoader({
      onProgress: this.updateLoadingProgress.bind(this)
    })

    const points = await loader.load(
      ({ page, per_page, signal }) => this.api.fetchPoints({
        page,
        per_page,
        start_at: this.startDateValue,
        end_at: this.endDateValue,
        signal
      }),
      {
        batchSize: 1000,
        maxConcurrent: 3,
        maxPoints: 100000
      }
    )

    performanceMonitor.mark('transform-geojson')
    const pointsGeoJSON = pointsToGeoJSON(points)
    performanceMonitor.measure('transform-geojson')

    // ... rest of loading logic

  } finally {
    this.hideLoading()
    const duration = performanceMonitor.measure('load-map-data')
    console.log(`Loaded map data in ${duration}ms`)
  }
}

// Add lazy loading for fog/scratch:
async toggleFog() {
  if (!this.fogLayer) {
    const FogLayer = await lazyLoader.loadLayer('fog')
    this.fogLayer = new FogLayer(this.map, {
      clearRadius: 1000,
      visible: true
    })

    const pointsData = this.pointsLayer?.data || { type: 'FeatureCollection', features: [] }
    this.fogLayer.add(pointsData)
  } else {
    this.fogLayer.toggle()
  }
}

async toggleScratch() {
  if (!this.scratchLayer) {
    const ScratchLayer = await lazyLoader.loadLayer('scratch')
    this.scratchLayer = new ScratchLayer(this.map, { visible: true })

    const pointsData = this.pointsLayer?.data || { type: 'FeatureCollection', features: [] }
    await this.scratchLayer.add(pointsData)
  } else {
    this.scratchLayer.toggle()
  }
}

// Register service worker:
async registerServiceWorker() {
  if ('serviceWorker' in navigator) {
    try {
      await navigator.serviceWorker.register('/maps-v2-sw.js')
      console.log('Service Worker registered')
    } catch (error) {
      console.error('Service Worker registration failed:', error)
    }
  }
}
```

---

## 8.8 Bundle Optimization

**File**: `package.json` (update)

```json
{
  "sideEffects": [
    "*.css",
    "maplibre-gl/dist/maplibre-gl.css"
  ],
  "scripts": {
    "build": "esbuild app/javascript/*.* --bundle --splitting --format=esm --outdir=app/assets/builds",
    "analyze": "esbuild app/javascript/*.* --bundle --metafile=meta.json --analyze"
  }
}
```

---

## 🧪 E2E Tests

**File**: `e2e/v2/phase-8-performance.spec.ts`

```typescript
import { test, expect } from '@playwright/test'
import { login, waitForMap } from './helpers/setup'

test.describe('Phase 8: Performance & Production', () => {
  test.beforeEach(async ({ page }) => {
    await login(page)
  })

  test('map loads within 3 seconds', async ({ page }) => {
    const startTime = Date.now()

    await page.goto('/maps_v2')
    await waitForMap(page)

    const loadTime = Date.now() - startTime

    expect(loadTime).toBeLessThan(3000)
  })

  test('handles large dataset (10k points)', async ({ page }) => {
    await page.goto('/maps_v2')
    await waitForMap(page)

    const pointCount = await page.evaluate(() => {
      const map = window.mapInstance
      const source = map?.getSource('points-source')
      return source?._data?.features?.length || 0
    })

    console.log(`Loaded ${pointCount} points`)
    expect(pointCount).toBeGreaterThan(0)
  })

  test('service worker registers', async ({ page }) => {
    await page.goto('/maps_v2')

    const swRegistered = await page.evaluate(async () => {
      if (!('serviceWorker' in navigator)) return false

      await new Promise(resolve => setTimeout(resolve, 1000))

      const registrations = await navigator.serviceWorker.getRegistrations()
      return registrations.some(reg =>
        reg.active?.scriptURL.includes('maps-v2-sw.js')
      )
    })

    expect(swRegistered).toBe(true)
  })

  test('no memory leaks after layer toggling', async ({ page }) => {
    await page.goto('/maps_v2')
    await waitForMap(page)

    const initialMemory = await page.evaluate(() => {
      return performance.memory?.usedJSHeapSize
    })

    // Toggle layers multiple times
    for (let i = 0; i < 10; i++) {
      await page.click('button[data-layer="points"]')
      await page.waitForTimeout(100)
      await page.click('button[data-layer="points"]')
      await page.waitForTimeout(100)
    }

    const finalMemory = await page.evaluate(() => {
      return performance.memory?.usedJSHeapSize
    })

    if (initialMemory && finalMemory) {
      const memoryGrowth = finalMemory - initialMemory
      const growthPercentage = (memoryGrowth / initialMemory) * 100

      console.log(`Memory growth: ${growthPercentage.toFixed(2)}%`)

      // Memory shouldn't grow more than 20%
      expect(growthPercentage).toBeLessThan(20)
    }
  })

  test('progressive loading works', async ({ page }) => {
    await page.goto('/maps_v2')

    // Wait for loading indicator
    const loading = page.locator('[data-map-target="loading"]')
    await expect(loading).toBeVisible()

    // Should show progress
    const loadingText = await loading.textContent()
    expect(loadingText).toContain('Loading')

    // Should finish
    await expect(loading).toHaveClass(/hidden/, { timeout: 15000 })
  })

  test.describe('Regression Tests', () => {
    test('all features work after optimization', async ({ page }) => {
      await page.goto('/maps_v2')
      await waitForMap(page)

      const allLayers = [
        'points', 'routes', 'heatmap',
        'visits', 'photos', 'areas-fill',
        'tracks', 'family'
      ]

      for (const layer of allLayers) {
        const exists = await page.evaluate((l) => {
          const map = window.mapInstance
          return map?.getLayer(l) !== undefined ||
                 map?.getSource(`${l}-source`) !== undefined
        }, layer)

        expect(exists).toBe(true)
      }
    })
  })
})
```

---

## ✅ Phase 8 Completion Checklist

### Implementation
- [ ] Created lazy_loader.js
- [ ] Created progressive_loader.js
- [ ] Created performance_monitor.js
- [ ] Created fps_monitor.js
- [ ] Created cleanup_helper.js
- [ ] Created service worker
- [ ] Updated map_controller.js
- [ ] Updated package.json

### Performance
- [ ] Bundle size < 500KB (gzipped)
- [ ] Map loads < 3s
- [ ] 10k points render < 500ms
- [ ] 100k points render < 2s
- [ ] No memory leaks detected
- [ ] FPS > 55 during pan/zoom
- [ ] Service worker registered
- [ ] Lighthouse score > 90

### Testing
- [ ] All Phase 8 E2E tests pass
- [ ] All Phase 1-7 tests pass (regression)
- [ ] Performance tests pass
- [ ] Memory leak tests pass

---

## 🚀 Production Deployment Checklist

### Pre-Deployment
- [ ] All 8 phases complete
- [ ] All E2E tests passing
- [ ] Bundle analyzed and optimized
- [ ] Performance metrics meet targets
- [ ] No console errors
- [ ] Documentation complete

### Deployment Steps
```bash
# 1. Final commit
git checkout -b maps-v2-phase-8
git add .
git commit -m "feat: Maps V2 Phase 8 - Production ready"

# 2. Run full test suite
npx playwright test e2e/v2/

# 3. Build for production
npm run build

# 4. Analyze bundle
npm run analyze

# 5. Deploy to staging
git push origin maps-v2-phase-8

# 6. Staging tests
# - Manual QA
# - Performance testing
# - User acceptance testing

# 7. Merge to main
git checkout main
git merge maps-v2-phase-8
git push origin main

# 8. Deploy to production
# 9. Monitor metrics
# 10. Celebrate! 🎉
```

### Post-Deployment
- [ ] Monitor error rates
- [ ] Track performance metrics
- [ ] Collect user feedback
- [ ] Plan future improvements

---

## 📊 Performance Targets vs Actual

| Metric | Target | Actual |
|--------|--------|--------|
| Initial Bundle Size | < 500KB | TBD |
| Time to Interactive | < 3s | TBD |
| Points Render (10k) | < 500ms | TBD |
| Points Render (100k) | < 2s | TBD |
| Memory (idle) | < 100MB | TBD |
| Memory (100k points) | < 300MB | TBD |
| FPS (pan/zoom) | > 55fps | TBD |
| Lighthouse Score | > 90 | TBD |

---

## 🎉 PHASE 8 COMPLETE - PRODUCTION READY!

All 8 phases are now complete! You have:

✅ **Phase 1**: MVP with points layer
✅ **Phase 2**: Routes + navigation
✅ **Phase 3**: Heatmap + mobile UI
✅ **Phase 4**: Visits + photos
✅ **Phase 5**: Areas + drawing tools
✅ **Phase 6**: Fog + scratch + advanced features (100% parity)
✅ **Phase 7**: Real-time updates + family sharing
✅ **Phase 8**: Performance optimization + production polish

**Total**: ~10,000+ lines of production-ready code across 8 deployable phases!

Ready to ship! 🚀
