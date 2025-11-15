# Maps V2 - Incremental Implementation Phases

## Philosophy: Progressive Enhancement

Each phase delivers a **working, deployable application** with incremental features. Every phase includes:
- ✅ Production-ready code
- ✅ Complete E2E tests (Playwright)
- ✅ Deployment checklist
- ✅ Rollback strategy

You can **deploy after any phase** and have a functional map application.

---

## Phase Overview

| Phase | Features | MVP Status | Deploy? | Timeline |
|-------|----------|------------|---------|----------|
| **Phase 1** | Basic map + Points layer | ✅ MVP | ✅ Yes | Week 1 |
| **Phase 2** | Routes + Date navigation | ✅ Enhanced | ✅ Yes | Week 2 |
| **Phase 3** | Heatmap + Mobile UI | ✅ Enhanced | ✅ Yes | Week 3 |
| **Phase 4** | Visits + Photos | ✅ Enhanced | ✅ Yes | Week 4 |
| **Phase 5** | Areas + Drawing tools | ✅ Enhanced | ✅ Yes | Week 5 |
| **Phase 6** | Fog + Scratch + Advanced | ✅ Full Parity | ✅ Yes | Week 6 |
| **Phase 7** | Real-time + Family sharing | ✅ Full Parity | ✅ Yes | Week 7 |
| **Phase 8** | Performance + Polish | ✅ Production | ✅ Yes | Week 8 |

---

## Incremental Feature Progression

### Phase 1: MVP - Basic Map (Week 1)
**Goal**: Minimal viable map with points visualization

**Features**:
- ✅ MapLibre map initialization
- ✅ Points layer with clustering
- ✅ Basic popup on point click
- ✅ Simple date range selector (single month)
- ✅ API client for points endpoint
- ✅ Loading states

**E2E Tests** (`e2e/v2/phase-1-mvp.spec.ts`):
- Map loads successfully
- Points render on map
- Clicking point shows popup
- Date selector changes data

**Deploy Decision**: Basic location history viewer

---

### Phase 2: Routes + Navigation (Week 2)
**Goal**: Add routes and better date navigation

**Features** (builds on Phase 1):
- ✅ Routes layer (speed-colored lines)
- ✅ Date picker with Previous/Next day/week/month
- ✅ Layer toggle controls (Points, Routes)
- ✅ Zoom controls
- ✅ Auto-fit bounds to data

**E2E Tests** (`e2e/v2/phase-2-routes.spec.ts`):
- Routes render correctly
- Date navigation works
- Layer toggles work
- Map bounds adjust to data

**Deploy Decision**: Full navigation + routes visualization

---

### Phase 3: Heatmap + Mobile (Week 3)
**Goal**: Add heatmap and mobile-first UI

**Features** (builds on Phase 2):
- ✅ Heatmap layer
- ✅ Bottom sheet UI (mobile)
- ✅ Touch gestures (pinch, pan, swipe)
- ✅ Settings panel
- ✅ Responsive breakpoints

**E2E Tests** (`e2e/v2/phase-3-mobile.spec.ts`):
- Heatmap renders
- Bottom sheet works on mobile
- Touch gestures functional
- Settings persist

**Deploy Decision**: Mobile-optimized map viewer

---

### Phase 4: Visits + Photos (Week 4)
**Goal**: Add visits detection and photo integration

**Features** (builds on Phase 3):
- ✅ Visits layer (suggested + confirmed)
- ✅ Photos layer with camera icons
- ✅ Visits drawer with search/filter
- ✅ Photo popup with preview
- ✅ Visit statistics

**E2E Tests** (`e2e/v2/phase-4-visits.spec.ts`):
- Visits render with correct colors
- Photos display on map
- Visits drawer opens/filters
- Photo popup shows image

**Deploy Decision**: Full location + visit tracking

---

### Phase 5: Areas + Drawing (Week 5)
**Goal**: Add area management and drawing tools

**Features** (builds on Phase 4):
- ✅ Areas layer
- ✅ Area selector (rectangle selection)
- ✅ Area drawer (create circular areas)
- ✅ Area management UI
- ✅ Tracks layer

**E2E Tests** (`e2e/v2/phase-5-areas.spec.ts`):
- Areas render on map
- Drawing tools work
- Area selection functional
- Areas persist after creation

**Deploy Decision**: Interactive area management

---

### Phase 6: Fog + Scratch + Advanced (Week 6)
**Goal**: Advanced visualization layers

**Features** (builds on Phase 5):
- ✅ Fog of war layer (canvas-based)
- ✅ Scratch map layer (visited countries)
- ✅ Keyboard shortcuts
- ✅ Click handler (centralized)
- ✅ Toast notifications

**E2E Tests** (`e2e/v2/phase-6-advanced.spec.ts`):
- Fog layer renders correctly
- Scratch map highlights countries
- Keyboard shortcuts work
- Notifications appear

**Deploy Decision**: 100% V1 feature parity

---

### Phase 7: Real-time + Family (Week 7)
**Goal**: Real-time updates and family sharing

**Features** (builds on Phase 6):
- ✅ ActionCable integration
- ✅ Real-time point updates
- ✅ Family layer (shared locations)
- ✅ Live notifications
- ✅ WebSocket reconnection

**E2E Tests** (`e2e/v2/phase-7-realtime.spec.ts`):
- Real-time updates appear
- Family locations show
- WebSocket reconnects
- Notifications real-time

**Deploy Decision**: Full collaborative features

---

### Phase 8: Performance + Production Polish (Week 8)
**Goal**: Optimize for production deployment

**Features** (builds on Phase 7):
- ✅ Lazy loading controllers
- ✅ Progressive data loading
- ✅ Performance monitoring
- ✅ Service worker (offline)
- ✅ Memory leak fixes
- ✅ Bundle optimization

**E2E Tests** (`e2e/v2/phase-8-performance.spec.ts`):
- Large datasets perform well
- Offline mode works
- No memory leaks
- Performance metrics met

**Deploy Decision**: Production-ready

---

## Testing Strategy

### E2E Test Structure

```
e2e/
└── v2/
    ├── phase-1-mvp.spec.ts           # Basic map + points
    ├── phase-2-routes.spec.ts        # Routes + navigation
    ├── phase-3-mobile.spec.ts        # Heatmap + mobile
    ├── phase-4-visits.spec.ts        # Visits + photos
    ├── phase-5-areas.spec.ts         # Areas + drawing
    ├── phase-6-advanced.spec.ts      # Fog + scratch
    ├── phase-7-realtime.spec.ts      # Real-time + family
    ├── phase-8-performance.spec.ts   # Performance tests
    └── helpers/
        ├── setup.ts                  # Common setup
        └── assertions.ts             # Custom assertions
```

### Running Tests

```bash
# Run all V2 tests
npx playwright test e2e/v2/

# Run specific phase
npx playwright test e2e/v2/phase-1-mvp.spec.ts

# Run in headed mode (watch)
npx playwright test e2e/v2/phase-1-mvp.spec.ts --headed

# Run with UI
npx playwright test e2e/v2/ --ui
```

---

## Deployment Strategy

### After Each Phase

1. **Run E2E tests**
   ```bash
   npx playwright test e2e/v2/phase-X-*.spec.ts
   ```

2. **Run previous phase tests** (regression)
   ```bash
   npx playwright test e2e/v2/phase-[1-X]-*.spec.ts
   ```

3. **Deploy to staging**
   ```bash
   git checkout -b maps-v2-phase-X
   # Deploy to staging environment
   ```

4. **Manual QA checklist** (in each phase guide)

5. **Deploy to production** (if approved)

### Rollback Strategy

Each phase is self-contained. If Phase N has issues:

```bash
# Revert to Phase N-1
git checkout maps-v2-phase-N-1
# Redeploy
```

---

## Progress Tracking

### Phase Completion Checklist

For each phase:
- [ ] All code implemented
- [ ] E2E tests passing
- [ ] Previous phase tests passing (regression)
- [ ] Manual QA complete
- [ ] Deployed to staging
- [ ] User acceptance testing
- [ ] Performance acceptable
- [ ] Documentation updated

### Example Workflow

```bash
# Week 1: Phase 1
- Implement Phase 1 code
- Write e2e/v2/phase-1-mvp.spec.ts
- All tests pass ✅
- Deploy to staging ✅
- User testing ✅
- Deploy to production ✅

# Week 2: Phase 2
- Implement Phase 2 code (on top of Phase 1)
- Write e2e/v2/phase-2-routes.spec.ts
- Run phase-1-mvp.spec.ts (regression) ✅
- Run phase-2-routes.spec.ts ✅
- Deploy to staging ✅
- User testing ✅
- Deploy to production ✅

# Continue...
```

---

## Feature Flags

Use feature flags for gradual rollout:

```ruby
# config/features.yml
maps_v2:
  enabled: true
  phases:
    phase_1: true  # MVP
    phase_2: true  # Routes
    phase_3: true  # Mobile
    phase_4: false # Visits (not deployed yet)
    phase_5: false
    phase_6: false
    phase_7: false
    phase_8: false
```

Enable phases progressively as they're tested and approved.

---

## File Organization

### Phase-Based Modules

Each phase adds new files without modifying previous:

```javascript
// Phase 1
app/javascript/maps_v2/
├── controllers/map_controller.js        # Phase 1
├── services/api_client.js               # Phase 1
├── layers/points_layer.js               # Phase 1
└── utils/geojson_transformers.js        # Phase 1

// Phase 2 adds:
├── controllers/date_picker_controller.js # Phase 2
├── layers/routes_layer.js                # Phase 2
└── components/layer_controls.js          # Phase 2

// Phase 3 adds:
├── controllers/bottom_sheet_controller.js # Phase 3
├── layers/heatmap_layer.js                # Phase 3
└── utils/gestures.js                      # Phase 3

// etc...
```

---

## Benefits of This Approach

✅ **Deployable at every step** - No waiting 8 weeks for first deploy
✅ **Easy testing** - Each phase has focused E2E tests
✅ **Safe rollback** - Can revert to any previous phase
✅ **User feedback** - Get feedback early and often
✅ **Risk mitigation** - Small, incremental changes
✅ **Team velocity** - Can parallelize some phases
✅ **Business value** - Deliver value incrementally

---

## Next Steps

1. **Review this overview** - Does the progression make sense?
2. **Restructure PHASE_X.md files** - Reorganize content by new phases
3. **Create E2E test templates** - One per phase
4. **Update README.md** - Link to new phase structure
5. **Begin Phase 1** - Start with MVP implementation

---

## Questions to Consider

- Should Phase 1 be even simpler? (e.g., no clustering initially?)
- Should we add a Phase 0 for setup/dependencies?
- Any features that should move to earlier phases?
- Any features that can be deferred to later?

Let me know if this structure works, and I'll restructure the existing PHASE files accordingly!
