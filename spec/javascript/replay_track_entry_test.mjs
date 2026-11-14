import assert from "node:assert/strict"
import test from "node:test"
import { MapReplayActions } from "controllers/maps/maplibre/map_replay"
import { ReplayManager } from "maps_maplibre/managers/replay_manager"

async function replayFrom(trackStart, timezone) {
  const manager = new ReplayManager({ timezone })
  manager.setPoints([{ timestamp: Date.parse(trackStart) / 1000 }])

  const seeded = {}
  await new MapReplayActions({
    hasReplayPanelTarget: true,
    replayPanelTarget: { classList: { contains: () => true } },
    replayPanel: {
      isPlaying: false,
      manager,
      ensureOpen: async () => {},
      goToDay: (day) => {
        seeded.day = day
      },
      setMinute: (minute) => {
        seeded.minute = minute
      },
      startPlayback: () => {
        seeded.started = true
      },
    },
  }).replayTrack({ currentTarget: { dataset: { trackStart } } })
  return seeded
}

test("seeds replay with the configured day and minute east of UTC", async () => {
  assert.deepEqual(await replayFrom("2025-01-15T20:00:00Z", "Asia/Tokyo"), {
    day: "2025-01-16",
    minute: 300,
    started: true,
  })
})

test("seeds replay with the configured day and minute west of UTC", async () => {
  assert.deepEqual(
    await replayFrom("2025-01-15T03:00:00Z", "America/Los_Angeles"),
    { day: "2025-01-14", minute: 1140, started: true },
  )
})
