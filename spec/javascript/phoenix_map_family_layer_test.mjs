import assert from "node:assert/strict"
import { test } from "node:test"
import { createMapFamilyLayer } from "../../app-phoenix/assets/js/map/family/host.js"
import {
  Element,
  fixture as hostFixture,
} from "./support/native_m6_host_fixture.mjs"

function fixture() {
  const polls = new Set(),
    paints = [],
    reads = [],
    flights = []
  const nodes = []
  const node = () => ({
    isConnected: true,
    hidden: false,
    dataset: {},
    children: [],
    setAttribute(k, v) {
      this[k] = v
    },
    append(...c) {
      this.children.push(...c)
    },
    replaceChildren(...c) {
      this.children = c
    },
    addEventListener(e, f) {
      this[e] = f
    },
  })
  const list = node(),
    empty = node(),
    status = node()
  const root = {
    querySelector(s) {
      return s === "#native-family-members"
        ? list
        : s === "[data-map-family-empty]"
          ? empty
          : status
    },
    ownerDocument: {
      createElement() {
        const n = node()
        nodes.push(n)
        return n
      },
    },
  }
  const reader = {
    async read(resource, params) {
      reads.push({ resource, params })
      return {
        data:
          resource === "family_locations"
            ? {
                locations: [
                  {
                    user_id: 7,
                    name: "<member>",
                    address: "<script>Street & City</script>",
                    email: "member@example.invalid",
                    longitude: 13.5,
                    latitude: 52.4,
                    timestamp: 1770000000,
                  },
                ],
              }
            : { members: [] },
      }
    },
  }
  const timers = {
    setInterval(f) {
      polls.add(f)
      return f
    },
    clearInterval(f) {
      polls.delete(f)
    },
    setTimeout() {
      return 1
    },
    clearTimeout() {},
  }
  let released = 0
  const owner = createMapFamilyLayer({
    map: {
      flyTo(receipt) {
        flights.push(receipt)
      },
    },
    reader,
    root,
    timers,
    createOverlay() {
      return {
        replace(...rows) {
          paints.push(rows)
        },
        clear() {
          paints.push([[]])
        },
        destroy() {
          released++
        },
      }
    },
  })
  const config = {
    familyEnabled: true,
    locale: "de",
    range: {
      timezone: "Europe/Berlin",
      startAt: "2026-06-01T00:00",
      endAt: "2026-06-02T23:59",
    },
    uiLabels: { "messages.centered_on_family_member": "Zentriert" },
  }
  return {
    owner,
    reader,
    polls,
    paints,
    reads,
    flights,
    list,
    nodes,
    status,
    config,
    get released() {
      return released
    },
  }
}

test("main map Family layer reads admitted locations history and renders safe centering controls", async () => {
  const f = fixture()
  await f.owner.update({ ...f.config, familyEnabled: false })
  assert.equal(f.reads.length, 0)
  await f.owner.update(f.config)
  assert.deepEqual(
    f.reads.map((r) => r.resource),
    ["family_locations", "family_history"],
  )
  assert.deepEqual(f.reads[1].params, {
    start_at: f.config.range.startAt,
    end_at: f.config.range.endAt,
  })
  assert.equal(f.list.hidden, false)
  const button = f.nodes.find((n) => n.type === "button")
  assert.match(button.textContent, /<member>/)
  assert.equal(button.children[0].textContent, "<script>Street & City</script>")
  assert.equal(button.children[0].innerHTML, undefined)
  button.click()
  assert.deepEqual(f.flights, [{ center: [13.5, 52.4], zoom: 15 }])
  assert.equal(f.status.textContent, "Zentriert")
  assert.equal(f.polls.size, 1)
  f.owner.destroy()
  assert.equal(f.polls.size, 0)
  assert.equal(f.released, 1)
})
test("disabling Family layer clears data and rejects a late noncooperative read", async () => {
  const f = fixture()
  await f.owner.update(f.config)
  let resolve
  const pending = new Promise((r) => {
    resolve = r
  })
  f.reader.read = () => pending
  const reading = f.owner.update(f.config)
  f.owner.clear()
  await f.owner.update({ ...f.config, familyEnabled: false })
  resolve({
    data: {
      locations: [{ user_id: 9, latitude: 52, longitude: 13 }],
      members: [],
    },
  })
  await reading
  assert.equal(f.list.hidden, true)
  assert.deepEqual(f.list.children, [])
  assert.deepEqual(f.paints.at(-1), [[]])
  assert.equal(f.polls.size, 0)
  f.owner.destroy()
})
test("Family refresh failure clears previous visible data without failing the map owner", async () => {
  const f = fixture()
  await f.owner.update(f.config)
  f.reader.read = async () => {
    throw new Error("synthetic refusal")
  }
  await f.owner.update(f.config)
  assert.deepEqual(f.list.children, [])
  assert.deepEqual(f.paints.at(-1), [[]])
  f.owner.destroy()
})
test("destroyed Family layer cannot restart its polling or publish late rows", async () => {
  const f = fixture()
  await f.owner.update(f.config)
  const poll = [...f.polls][0]
  f.owner.destroy()
  const count = f.reads.length
  await poll()
  await f.owner.update(f.config)
  assert.equal(f.reads.length, count)
  assert.deepEqual(f.list.children, [])
  assert.equal(f.polls.size, 0)
})

test("production map owner mounts one scoped Family overlay and clears it on toggle", async () => {
  const f = hostFixture({ familyEnabled: true })
  const list = new Element()
  f.nodes.set("#native-family-members", list)
  const read = f.reader.read
  f.reader.read = async (resource, params) => {
    if (!resource.startsWith("family_")) return read(resource, params)
    f.reads.push({ resource, params })
    return {
      data:
        resource === "family_locations"
          ? {
              locations: [
                {
                  user_id: 7,
                  email: "member@example.invalid",
                  latitude: 52.4,
                  longitude: 13.5,
                  timestamp: 1770000000,
                },
              ],
            }
          : { members: [] },
    }
  }
  try {
    assert.equal(await f.owner.mount(), "ready")
    assert.equal(f.owner.map, f.map)
    assert.equal(
      f.reads.filter((r) => r.resource === "family_locations").length,
      1,
    )
    assert.equal(f.sources.get("family-members").data.features.length, 1)
    assert.equal(list.children.length, 1)
    await f.owner.update({
      ...f.owner.config,
      familyEnabled: false,
      revision: 2,
    })
    assert.equal(list.hidden, true)
    assert.equal(f.sources.has("family-members"), false)
    assert.equal(f.layers.has("family-circles"), false)
  } finally {
    f.owner.destroy()
  }
})

test("new Family refresh keeps latest admitted rows when an older reader ignores abort", async () => {
  const f = fixture()
  let resolve
  const pending = new Promise((r) => {
    resolve = r
  })
  f.reader.read = () => pending
  const old = f.owner.update(f.config)
  f.reader.read = async (resource) => ({
    data:
      resource === "family_locations"
        ? {
            locations: [
              {
                user_id: 8,
                name: "Current",
                latitude: 52,
                longitude: 13,
                timestamp: 1770000000,
              },
            ],
          }
        : { members: [] },
  })
  try {
    await f.owner.update(f.config)
    resolve({
      data: {
        locations: [
          {
            user_id: 9,
            name: "Old",
            latitude: 52,
            longitude: 13,
            timestamp: 1770000000,
          },
        ],
        members: [],
      },
    })
    await old
    assert.equal(f.paints.at(-1)[0][0].user_id, 8)
    assert.match(f.list.children[0].textContent, /Current/)
  } finally {
    f.owner.destroy()
  }
})

test("main map Family member history retains sharing date and source day count", async () => {
  const f = fixture()
  f.config.uiLabels["family.sharing_since.other"] = "Seit {date} ({count} Tage)"
  const read = f.reader.read
  f.reader.read = async (resource, params) =>
    resource === "family_history"
      ? {
          data: {
            members: [
              {
                user_id: 7,
                sharing_since: new Date(
                  Date.now() - 2 * 86400000 - 1000,
                ).toISOString(),
                points: [
                  [52.4, 13.5],
                  [52.5, 13.6],
                ],
              },
            ],
          },
        }
      : read(resource, params)
  try {
    await f.owner.update(f.config)
    const info = f.nodes.find((n) => n["data-member-info"] === "7")
    assert.ok(info)
    assert.match(info.textContent, /Seit .+ \(2 Tage\)/)
  } finally {
    f.owner.destroy()
  }
})

test("main map Family list retains source update timestamp in the profile timezone", async () => {
  const f = fixture()
  const read = f.reader.read
  f.reader.read = async (resource, params) => {
    const result = await read(resource, params)
    if (resource === "family_locations")
      result.data.locations[0].updated_at = "2026-06-02T12:34:00Z"
    return result
  }
  try {
    await f.owner.update(f.config)
    const button = f.nodes.find((n) => n.type === "button")
    const expected = new Intl.DateTimeFormat("de", {
      month: "short",
      day: "numeric",
      hour: "numeric",
      minute: "2-digit",
      timeZone: "Europe/Berlin",
    }).format(new Date("2026-06-02T12:34:00Z"))
    assert.ok(button.textContent.includes(expected))
  } finally {
    f.owner.destroy()
  }
})

test("main map Family loaded status retains singular and plural counts", async () => {
  const f = fixture()
  f.config.uiLabels["family.loaded_members.one"] = "Ein Mitglied"
  f.config.uiLabels["family.loaded_members.other"] = "{count} Mitglieder"
  try {
    await f.owner.update(f.config)
    assert.equal(f.status.textContent, "Ein Mitglied")
    const read = f.reader.read
    f.reader.read = async (resource, params) => {
      const result = await read(resource, params)
      if (resource === "family_locations")
        result.data.locations.push({ ...result.data.locations[0], user_id: 8 })
      return result
    }
    await f.owner.update(f.config)
    assert.equal(f.status.textContent, "2 Mitglieder")
  } finally {
    f.owner.destroy()
  }
})
