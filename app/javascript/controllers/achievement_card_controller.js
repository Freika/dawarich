import { Controller } from "@hotwired/stimulus"

const PROXIMITY = 30
const HYSTERESIS = 12
const DEPTH = 13
const RIM = 0.3
const LIGHT_THROW = 42
const SHADOW_ALPHA = 0.1
const RADIANS = Math.PI / 180

const PROPS = [
  "--ry",
  "--rx",
  "--mx",
  "--my",
  "--fo",
  "--sc",
  "--gl",
  "--px",
  "--py",
  "--rimx",
  "--rimy",
  "--sx",
  "--sy",
  "--sa",
  "--gx",
  "--gy",
]

export default class extends Controller {
  static values = {
    tilt: { type: Number, default: 12 },
    holo: { type: Number, default: 0.7 },
    locked: { type: Boolean, default: false },
  }

  connect() {
    this.engaged = false
    this.track = this.track.bind(this)
    document.addEventListener("pointermove", this.track)
  }

  disconnect() {
    document.removeEventListener("pointermove", this.track)
  }

  // Engagement is proximity-based rather than enter/leave on the element. The
  // card scales to 1.04 while the wrap carrying the listener does not, so it
  // overhangs its own hit area by a few px — and in that halo the pointer sits
  // on the card but off the listener, flipping the state on every sub-pixel
  // move. Releasing only past PROXIMITY + HYSTERESIS gives the boundary a dead
  // band it cannot oscillate inside.
  track(event) {
    if (this.lockedValue) return

    const rect = this.element.getBoundingClientRect()
    const away = Math.hypot(
      Math.max(rect.left - event.clientX, 0, event.clientX - rect.right),
      Math.max(rect.top - event.clientY, 0, event.clientY - rect.bottom),
    )

    if (away > (this.engaged ? PROXIMITY + HYSTERESIS : PROXIMITY)) {
      if (this.engaged) {
        this.engaged = false
        this.clear()
      }
      return
    }

    this.engaged = true
    this.apply(rect, event.clientX, event.clientY)
  }

  move(event) {
    this.track(event)
  }

  leave() {
    // the pointer may still be inside the proximity zone, and mouseleave fires
    // at the element edge — exactly the boundary proximity exists to soften
    if (this.engaged) return

    this.clear()
  }

  apply(rect, clientX, clientY) {
    // clamped: engaging from outside the card must not drive the tilt past its
    // own maximum, or the anticipation reads as a lurch
    const px = Math.min(1, Math.max(0, (clientX - rect.left) / rect.width))
    const py = Math.min(1, Math.max(0, (clientY - rect.top) / rect.height))
    const tilt = this.tiltValue
    const ry = (px - 0.5) * 2 * tilt
    const rx = (0.5 - py) * 2 * tilt
    const set = (prop, value) => this.element.style.setProperty(prop, value)

    set("--ry", `${ry.toFixed(2)}deg`)
    set("--rx", `${rx.toFixed(2)}deg`)

    // Fixed overhead light rather than a cursor-locked one: the highlight
    // slides opposite the lean, the way foil catches a lamp that is not moving
    // with your hand.
    const throwFrom = tilt || 1
    const mx = 50 - (ry / throwFrom) * LIGHT_THROW
    const my = 50 + (rx / throwFrom) * LIGHT_THROW
    set("--mx", `${mx.toFixed(1)}%`)
    set("--my", `${my.toFixed(1)}%`)

    set("--fo", String(this.holoValue))
    set("--sc", "1.04")
    set("--gl", "1")

    // A point at depth d under a surface turned by θ projects d*tan(θ) to the
    // side, so the art's drift follows the angle rather than the tilt's numeric
    // value read as pixels.
    set("--px", `${(-Math.tan(ry * RADIANS) * DEPTH).toFixed(2)}px`)
    set("--py", `${(Math.tan(rx * RADIANS) * DEPTH).toFixed(2)}px`)

    // Card stock. The back face translates rigidly by
    // (-T*sin(rotateY), +T*sin(rotateX)), so the wall is the card swept along
    // that one vector. Splitting it per axis would leave a hole where the
    // corner belongs; only the two edges turning away ever show, which is what
    // a slab does.
    set("--rimx", `${(-ry * 0.6 * RIM).toFixed(2)}px`)
    set("--rimy", `${((2 + rx * 0.5) * RIM).toFixed(2)}px`)

    set("--sx", `${(-ry * 0.9).toFixed(1)}px`)
    set("--sy", `${(rx * 0.7).toFixed(1)}px`)
    set("--sa", String(SHADOW_ALPHA))

    set("--gx", `${(100 - mx).toFixed(1)}%`)
    set("--gy", `${(100 - my).toFixed(1)}%`)
  }

  clear() {
    for (const prop of PROPS) {
      this.element.style.removeProperty(prop)
    }
  }
}
