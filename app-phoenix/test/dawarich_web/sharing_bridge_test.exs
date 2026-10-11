defmodule DawarichWeb.SharingBridgeTest do
  use ExUnit.Case, async: true

  test "deferred Stimulus registration has no retired sharing stream write listener" do
    run("""
    import assert from "node:assert/strict";
    import fs from "node:fs";
    import vm from "node:vm";
    const listeners = [], registrations = [];
    const context = vm.createContext({window: {}, document: {
      addEventListener: name => listeners.push(name), removeEventListener() {}
    }});
    const dependency = new vm.SyntheticModule(["Application", "lazyLoadControllersFrom", "default"], function() {
      this.setExport("Application", class {async start() {} register(name) {registrations.push(name);} stop() {}});
      this.setExport("lazyLoadControllersFrom", () => {});
      this.setExport("default", class {});
    }, {context});
    await dependency.link(() => {}); await dependency.evaluate();
    const module = new vm.SourceTextModule(fs.readFileSync("priv/static/js/rails_bridge.js", "utf8"), {
      context, importModuleDynamically: () => dependency
    });
    await module.link(() => {}); await module.evaluate();
    const element = {addEventListener: name => listeners.push(name), removeAttribute() {},
      getAttribute: () => "stat-page", querySelectorAll: () => []};
    const bridge = module.namespace.railsBridge(element);
    await bridge.ready;
    assert.deepEqual(registrations, ["stat-page"]);
    assert.equal(bridge.onSubmit, undefined);
    assert.equal(bridge.onStream, undefined);
    assert.equal(listeners.includes("submit"), false);
    assert.equal(listeners.includes("turbo:before-stream-render"), false);
    """)
  end

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

  test "deferred controls wait for Stimulus handlers and retain initially disabled fields" do
    run("""
    import assert from "node:assert/strict";
    import fs from "node:fs";
    import vm from "node:vm";
    let release;
    const loading = new Promise(resolve => release = resolve);
    const context = vm.createContext({window: {}, document: {addEventListener() {}}});
    const dependency = new vm.SyntheticModule(["Application", "lazyLoadControllersFrom"], function() {
      this.setExport("Application", class {async start() {} register() {} stop() {}});
      this.setExport("lazyLoadControllersFrom", () => {});
    }, {context});
    await dependency.link(() => {});
    await dependency.evaluate();
    const module = new vm.SourceTextModule(fs.readFileSync("priv/static/js/rails_bridge.js", "utf8"), {
      context, importModuleDynamically: async () => {await loading; return dependency;}
    });
    await module.link(() => {});
    await module.evaluate();
    const fields = [{disabled: false}, {disabled: true}];
    const element = {addEventListener() {}, removeAttribute() {}, getAttribute: () => "",
      querySelectorAll: selector => selector.includes("button") ? fields : []};
    const bridge = module.namespace.railsBridge(element);
    assert.equal(fields[0].disabled, true);
    release();
    await bridge.ready;
    assert.equal(fields[0].disabled, false);
    assert.equal(fields[1].disabled, true);
    """)
  end

  test "deferred map flash rendering preserves each visible notice without a write bridge" do
    run("""
    import assert from "node:assert/strict";
    import fs from "node:fs";
    import vm from "node:vm";
    const appended = [];
    const context = vm.createContext({window: {}, document: {getElementById: () => ({appendChild: node => appended.push(node)})}});
    const module = new vm.SourceTextModule(fs.readFileSync("priv/static/js/rails_bridge.js", "utf8"), {context});
    await module.link(() => {}); await module.evaluate();
    const notices = [{textContent: "Saved"}, {textContent: "Try again"}];
    module.namespace.appendRailsFlash({querySelectorAll: () => notices});
    assert.deepEqual(appended, notices);
    """)
  end
end
