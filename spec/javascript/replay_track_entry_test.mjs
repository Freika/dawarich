import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const readSource = (path) =>
  readFile(new URL(`../../app/javascript/${path}`, import.meta.url), "utf8")
const importSource = (source) =>
  import(
    `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
  )

const { ReplayManager } = await importSource(
  (await readSource("maps_maplibre/managers/replay_manager.js")).replace(
    /^import[\s\S]*?from "[^"]+"\n/m,
    "",
  ),
)

const controllerSource = await readSource(
  "controllers/maps/maplibre_controller.js",
)
const methodStart = controllerSource.indexOf("async replayTrack(event) {")
const methodEnd = controllerSource.indexOf("async toggleTrackPoints(")
const { default: methods } = await importSource(
  `export default { ${controllerSource.slice(methodStart, methodEnd)} }`,
)

async function replayFrom(trackStart, timezone) {
  const manager = new ReplayManager({ timezone })
  manager.setPoints([{ timestamp: Date.parse(trackStart) / 1000 }])

  const seeded = {}
  await methods.replayTrack.call(
    {
      hasReplayPanelTarget: true,
      replayPanelTarget: { classList: { contains: () => true } },
      _ensureReplayPanel() {},
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
    },
    { currentTarget: { dataset: { trackStart } } },
  )
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
