import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const read = (path) =>
  readFile(new URL(`../../${path}`, import.meta.url), "utf8")
const moduleUrl = (source) =>
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
const cableUrl = moduleUrl(
  await read("vendor/assets/javascripts/actioncable.esm.js"),
)
const consumerUrl = moduleUrl(`
  import { createConsumer } from ${JSON.stringify(cableUrl)}
  export const commands = []
  const consumer = createConsumer("ws://127.0.0.1/cable")
  consumer.ensureActiveConnection = () => {}
  consumer.send = (command) => { commands.push(command); return false }
  export default consumer
`)
const { default: consumer, commands } = await import(consumerUrl)
const legacyUrl = moduleUrl(
  (await read("app/javascript/channels/family_locations_channel.js")).replace(
    '"./consumer"',
    JSON.stringify(consumerUrl),
  ),
)
const bootUrl = moduleUrl(
  (await read("app/javascript/channels/index.js")).replace(
    '"family_locations_channel"',
    JSON.stringify(legacyUrl),
  ),
)
const { createMapChannel } = await import(
  moduleUrl(
    (
      await read("app/javascript/maps_maplibre/channels/map_channel.js")
    ).replace('"../../channels/consumer"', JSON.stringify(consumerUrl)),
  )
)

test("the current map owns the family subscription across live mode changes", async (t) => {
  const original = globalThis.document
  globalThis.document = {
    querySelector: () => ({
      dataset: { familyMembersFeaturesValue: '{"family":true}' },
    }),
  }
  t.after(() => {
    for (const sub of [...consumer.subscriptions.subscriptions]) {
      sub.unsubscribe()
    }
    globalThis.document = original
  })
  await import(bootUrl)
  const id = '{"channel":"FamilyLocationsChannel"}'
  const connected = []
  const received = []
  const create = (enableLiveMode) =>
    createMapChannel({
      enableLiveMode,
      connected: (name) => connected.push(name),
      received: (message) => received.push(message),
    })
  const first = create(false)
  assert.equal(consumer.subscriptions.findAll(id).length, 1)
  first.unsubscribeAll()
  assert.ok(
    commands.some(
      (command) =>
        command.command === "unsubscribe" && command.identifier === id,
    ),
  )
  const current = create(true)
  assert.equal(consumer.subscriptions.findAll(id).length, 1)
  consumer.subscriptions.notify(id, "connected")
  const member = { user_id: 2, latitude: 52.55, longitude: 13.415 }
  consumer.subscriptions.notify(id, "received", member)
  assert.deepEqual(connected, ["family"])
  assert.deepEqual(received, [{ type: "family_location", member }])
  current.unsubscribeAll()
  assert.equal(consumer.subscriptions.findAll(id).length, 0)
})
