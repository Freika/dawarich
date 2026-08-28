// Frame schedule for a render: a hold on the empty map, an eased draw phase,
// and a hold on the finished route for the stats card.
const DEFAULT_INTRO_HOLD_SEC = 0.6
const DEFAULT_OUTRO_HOLD_SEC = 3

function easeInOutSine(t) {
  return (1 - Math.cos(Math.PI * t)) / 2
}

export function buildRenderPlan({
  durationSec,
  fps = 30,
  introHoldSec = DEFAULT_INTRO_HOLD_SEC,
  outroHoldSec = DEFAULT_OUTRO_HOLD_SEC,
}) {
  const totalFrames = Math.max(1, Math.round(durationSec * fps))
  let introFrames = Math.round(introHoldSec * fps)
  let outroFrames = Math.round(outroHoldSec * fps)

  const holdFrames = introFrames + outroFrames
  if (holdFrames >= totalFrames) {
    const scale = (totalFrames - 1) / holdFrames
    introFrames = Math.floor(introFrames * scale)
    outroFrames = Math.floor(outroFrames * scale)
  }

  return { fps, totalFrames, introFrames, outroFrames }
}

export function frameFraction(plan, frameIndex) {
  const { totalFrames, introFrames, outroFrames } = plan
  const i = Math.max(0, Math.min(totalFrames - 1, frameIndex))
  const drawFrames = totalFrames - introFrames - outroFrames
  if (i < introFrames) return 0
  if (i >= totalFrames - outroFrames) return 1
  return easeInOutSine((i - introFrames) / drawFrames)
}
