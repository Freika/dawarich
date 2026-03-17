# Dawarich Design System v2

> Canonical reference for web app, landing page (dawarich.app), iOS app, and Android app.
> All platforms MUST implement from these tokens. Platform-specific adaptations are noted where applicable.

## Design Philosophy

**Personal, warm, inviting** — Dawarich is a place where people review their life's journeys. The design should feel like opening a well-loved notebook, not like using an enterprise dashboard or a phone's native settings.

**Platform-independent brand** — The design system creates a "Dawarich" identity that feels owned, not borrowed from iOS or Android. Like Notion or Linear, Dawarich should look like itself everywhere.

**Key principles:**
- Warm backgrounds with subtle texture give depth without distraction
- Glass navbar creates a sense of layered depth
- Inter throughout keeps things clean; weight hierarchy creates distinction
- Green primary (`#3FBA4E`) connects to maps, nature, and movement
- Lift interactions feel tangible — things respond to touch like physical objects
- Timestamps-left timeline reads like a journal/log, not a chat thread

---

## Color Tokens

### Primary Palette

| Token | Light Mode | Dark Mode | Usage |
|-------|-----------|-----------|-------|
| `--color-primary` | `#3B82F6` | `#60A5FA` | Buttons, active states, links, track lines |
| `--color-primary-hover` | `#2563EB` | `#3B82F6` | Button/link hover |
| `--color-primary-light` | `rgba(59,130,246,0.10)` | `rgba(96,165,250,0.15)` | Tinted backgrounds, active tab bg |
| `--color-primary-subtle` | `rgba(59,130,246,0.20)` | `rgba(96,165,250,0.25)` | Borders on active elements |

### Semantic Colors

| Token | Light | Dark | Usage |
|-------|-------|------|-------|
| `--color-accent` | `#0D9488` | `#2DD4BF` | Secondary actions, visit markers, success/completed states |
| `--color-warning` | `#F59E0B` | `#FBBF24` | Pending status, caution states |
| `--color-danger` | `#EF4444` | `#F87171` | Error states, destructive actions, failed imports |
| `--color-info` | `#06B6D4` | `#22D3EE` | Processing status, informational badges |

### Surface Colors (Neutral with minimal warmth)

| Token | Light | Dark | Notes |
|-------|-------|------|-------|
| `--color-bg` | `#FAFAF9` | `#141414` | Page background |
| `--color-bg-elevated` | `#FFFFFF` | `#1C1C1C` | Cards, navbar, modals (DaisyUI `base-100`) |
| `--color-bg-sunken` | `#F5F5F3` | `#101010` | Inset areas, table headers (DaisyUI `base-200`/`base-300`) |
| `--color-bg-hover` | `#EFEFED` | `#282828` | Hover state for rows, nav items |

### Text Colors

| Token | Light | Dark | Usage |
|-------|-------|------|-------|
| `--color-text` | `#1A1A1A` | `#EAEAEA` | Primary body text, headings |
| `--color-text-secondary` | `#585858` | `#9A9A9A` | Secondary labels, metadata |
| `--color-text-tertiary` | `#999999` | `#636363` | Timestamps, placeholders, captions |

### Border & Shadow

| Token | Light | Dark |
|-------|-------|------|
| `--color-border` | `#E5E5E2` | `#2A2A2A` |
| `--shadow-color` | `rgba(0,0,0,0.05)` | `rgba(0,0,0,0.25)` |

---

## Typography

### Font Stack

| Role | Font | Fallback | Weight Range |
|------|------|----------|-------------|
| **All text** | Inter | system-ui, sans-serif | 400-700 |

Inter is used for everything — headings, body, labels. Weight and size create hierarchy, not font family.

### Type Scale

| Level | Size | Weight | Line Height | Usage |
|-------|------|--------|-------------|-------|
| H1 | 1.875rem (30px) | 700 | 1.3 | Page titles |
| H2 | 1.5rem (24px) | 700 | 1.3 | Section headers |
| H3 | 1.25rem (20px) | 600 | 1.3 | Card titles |
| H4 | 1.125rem (18px) | 600 | 1.3 | Sub-section headers |
| Body | 1rem (16px) | 400 | 1.6 | Default text |
| Small | 0.875rem (14px) | 400-500 | 1.5 | Labels, table cells |
| Caption | 0.75rem (12px) | 500 | 1.5 | Timestamps, badges |
| Overline | 0.72rem (11.5px) | 600 | 1.5 | Table headers (uppercase, 0.05em tracking) |

### Font Loading

Inter is loaded via the existing `inter-font` stylesheet link (already in the project).

**Native apps:** Bundle Inter. Do not use platform default fonts (SF Pro, Roboto).

---

## Spacing & Layout

### Spacing Scale (4px grid)

| Token | Value | Usage |
|-------|-------|-------|
| `--space-1` | 4px | Tight gaps (badge padding) |
| `--space-2` | 8px | Icon gaps, small padding |
| `--space-3` | 12px | Control padding |
| `--space-4` | 16px | Grid gap, section padding |
| `--space-5` | 20px | Card padding, page margins |
| `--space-6` | 24px | Section margins |
| `--space-8` | 32px | Large section gaps |

### Key Measurements

| Element | Value |
|---------|-------|
| Grid gap | 16px |
| Card padding | 20px |
| Navbar height | 64px |
| Map sidebar width | 400px (desktop), 100% (mobile) |
| Max content width | 1280px |
| Stat columns | 4 (desktop), 2 (tablet), 1 (mobile) |

---

## Shape

### Border Radius

| Element | Radius |
|---------|--------|
| Buttons, inputs | 6px |
| Cards, modals | 10px (`radius + 4`) |
| Badges | 99px (pill) |
| Pill tabs | 6px (individual), 8px (container) |
| Small elements (dots, indicators) | 50% |

### Shadows

Shadows are **very subtle** (0.05 opacity) with warm-tinted shadow color.

| Level | Value | Usage |
|-------|-------|-------|
| None | `none` | Default card state |
| Hover | `0 8px 20px var(--shadow-color)` | Card lift on hover |
| Button hover | `0 4px 12px rgba(primary, 0.35)` | Primary button lift |

---

## Component Specifications

### Navbar

**Style: Glass**
- Background: semi-transparent elevated surface (75% opacity)
- `backdrop-filter: blur(16px) saturate(1.5)`
- Bottom border: 1px solid `--color-border`
- Height: 64px
- **Native apps:** Use native blur/vibrancy API (UIBlurEffect on iOS, RenderEffect on Android)

### Tabs

**Style: Pill**
- Container: sunken background, 4px padding, rounded (`radius + 2`)
- Active tab: primary background, white text
- Inactive: transparent, tertiary text color
- Transition: 150ms ease
- **Native apps:** Use segmented control styling (but with Dawarich colors, not platform defaults)

### Cards

**Hover: Lift**
- Default: solid border, no shadow
- Hover: `transform: translateY(-3px)`, shadow appears
- Transition: 200ms ease
- **Native apps:** On press, use spring animation to scale(0.98), release to scale(1) with elevation change

### Badges

**Style: Filled (tinted background)**
- Background: 12% opacity of semantic color
- Text: semantic color at full saturation
- Padding: 2px 10px
- Border-radius: pill (99px)
- Font: 0.72rem, weight 500

### Buttons

**Hover: Lift**
- Default: solid fill
- Hover: `translateY(-1px)`, `box-shadow: 0 4px 12px rgba(primary, 0.35)`
- Transition: 150ms ease
- **Native apps:** Haptic feedback on press, spring scale animation

### Timeline

**Style: Timestamps Left**
- Two-column layout: fixed-width time column (48px) + content
- No vertical connecting line
- Time: 0.72rem, tertiary color, tabular-nums
- Entries separated by 1px border-bottom (sunken color)
- Visit entries: bold name + accent duration badge
- Journey entries: mode + distance + duration

### Stat Cards

**Style: Minimal**
- Centered value + label
- Value: heading font, 1.5rem, weight 700, semantic color, tabular-nums
- Label: 0.8rem, tertiary color
- No accent bars or tinted backgrounds

### Empty States

- Sunken background
- Dashed border (2px)
- Centered text + primary CTA button
- Guidance text in tertiary color
- Max-width 360px for text

---

## Background Texture

**Style: Grain (paper-like)**

Subtle SVG noise overlay at ~3% opacity (light) / ~4% opacity (dark). Creates a warm, tactile feel without interfering with content.

```css
body::before {
  content: '';
  position: fixed;
  inset: 0;
  pointer-events: none;
  z-index: 9999;
  opacity: 0.03; /* 0.04 in dark mode */
  background-image: url("data:image/svg+xml,..."); /* SVG feTurbulence noise */
  background-repeat: repeat;
  background-size: 256px;
}
```

**Native apps:** Use a tiled noise texture image asset as a fixed background overlay layer. Keep opacity consistent with web values.

**Landing page:** Can use more dramatic textures (gradient, topo lines) on hero sections while keeping grain for content areas.

---

## Dark Mode

Dark mode uses the **golden warmth** palette with desaturated, lighter tonal variants of all semantic colors.

**Key rules:**
- Primary green shifts from `#3FBA4E` to `#5AD468` (lighter, less saturated)
- Backgrounds use warm charcoal tones (not blue-tinted slate)
- Borders lighten but stay warm (`#2E2C22`, not `#334155`)
- Shadows increase in opacity (0.25) since dark backgrounds absorb more
- Grain overlay increases to 4% opacity

**Native apps:** Support automatic dark mode switching. Never invert colors — always use the explicit dark palette.

---

## Responsive Breakpoints

| Name | Width | Layout Changes |
|------|-------|---------------|
| Mobile | < 640px | Single column, full-width cards, stacked stat bar |
| Tablet | 640-1024px | 2-column grids, sidebar stacks above map |
| Desktop | > 1024px | Full layout, sidebar + map side-by-side, 3-column trip grid |

---

## Platform-Specific Notes

### Web App (Rails + DaisyUI + Tailwind)
- Implement via DaisyUI custom theme + Tailwind config extensions
- Use CSS custom properties for all tokens
- Grain texture via `::before` pseudo-element
- Glass navbar via `backdrop-filter`

### Landing Page (dawarich.app)
- Same tokens, same fonts
- Can use bolder texture on hero (topo lines, gradient)
- Glass navbar should scroll-transition from transparent to glass
- Consider larger type scale for marketing headings (2x body)

### iOS App
- Bundle Inter font (do not use SF Pro)
- Glass navbar: `UIBlurEffect.style = .systemThinMaterial` with tint
- Lift interactions: spring animations (`UISpringTimingParameters`)
- Pill tabs: custom segmented control, not `UISegmentedControl`
- Grain: `UIImageView` with tiled noise PNG at 3% opacity, `isUserInteractionEnabled = false`
- Respect Dynamic Type for body text; headings can use fixed sizes

### Android App
- Bundle Inter font (do not use Roboto)
- Glass navbar: `RenderEffect.createBlurEffect` (API 31+), fallback to solid with 90% opacity
- Lift interactions: `Modifier.graphicsLayer` with spring animation in Compose
- Pill tabs: custom `TabRow` with Dawarich styling
- Grain: `BitmapShader` with tiled noise, drawn as fixed overlay
- Use Material 3 shape system but override with Dawarich radii

### Shared Assets Needed
- Noise texture PNG (256x256, tileable) for grain overlay
- App icon using `#3FBA4E` green
- Inter font files (woff2 for web, ttf/otf for native)

---

## Migration Notes

### From Current Design (DaisyUI defaults)

| What | Before | After |
|------|--------|-------|
| Primary color | `#6366F1` (indigo) | `#3B82F6` (blue) |
| Heading font | Inter | Inter (unchanged) |
| Track color | `#6366F1` | `#3FBA4E` |
| Background | `#FFFFFF` / DaisyUI dark | Golden warm tones |
| Card hover | DaisyUI shadow | Lift (translateY) |
| Tabs | DaisyUI tabs-lifted | Pill style |
| Navbar | Solid `bg-base-100` | Glass (blur) |
| Badges | DaisyUI defaults | Filled (tinted) |
| Shadows | DaisyUI defaults | Very subtle (0.05) |
| Spacing | Inconsistent | 4px grid, 16px gap |

### DaisyUI Theme Configuration

```javascript
// tailwind.config.js
module.exports = {
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter var', ...defaultTheme.fontFamily.sans],
      },
    },
  },
  daisyui: {
    themes: [
      {
        dawarich: {
          'primary': '#3B82F6',
          'secondary': '#0D9488',
          'accent': '#0D9488',
          'neutral': '#1A1A1A',
          'base-100': '#FFFFFF',
          'base-200': '#F5F5F3',
          'base-300': '#E5E5E2',
          'info': '#06B6D4',
          'success': '#0D9488',
          'warning': '#F59E0B',
          'error': '#EF4444',
        },
        'dawarich-dark': {
          'primary': '#60A5FA',
          'secondary': '#2DD4BF',
          'accent': '#2DD4BF',
          'neutral': '#EAEAEA',
          'base-100': '#1C1C1C',
          'base-200': '#141414',
          'base-300': '#101010',
          'info': '#22D3EE',
          'success': '#2DD4BF',
          'warning': '#FBBF24',
          'error': '#F87171',
        },
      },
    ],
  },
}
```
