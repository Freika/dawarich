defmodule DawarichWeb.SharingBridgeTest do
  use ExUnit.Case, async: true

  test "native family consent hides the placeholder and revocation erases the map" do
    run("""
    import assert from "node:assert/strict";
    import { FamilyMap } from "./assets/js/map/shared/family_map.js";
    const events = new Map(), empty = {hidden: false}, canvas = {hidden: true, replaceChildren() {}};
    let removed = 0;
    class MapView {addControl() {} fitBounds() {} remove() {removed++;}}
    class Marker {setLngLat() {return this;} addTo() {return this;} remove() {}}
    const hook = {...FamilyMap, el: {closest: () => ({querySelectorAll: () => []}),
      querySelector: selector => selector.includes("empty") ? empty : canvas},
      loader: async () => ({maplibre: {Map: MapView, Marker, NavigationControl: class {}}, style: {}}),
      handleEvent(name, fn) {events.set(name, fn); return name;},
      removeHandleEvent(name) {events.delete(name);}, pushEvent() {}};
    hook.mounted();
    await events.get("family-locations")({locations: [{user_id: 1, latitude: 51, longitude: 12}]});
    assert.equal(empty.hidden, true);
    events.get("family-clear")({});
    assert.equal(empty.hidden, false);
    assert.equal(canvas.hidden, true);
    assert.equal(hook.locations.length, 0);
    assert.equal(removed, 1);
    hook.destroyed();
    assert.equal(events.size, 0);
    """)
  end

  defp run(script) do
    {output, status} =
      System.cmd("node", ["--experimental-vm-modules", "--input-type=module", "-e", script],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end
end
