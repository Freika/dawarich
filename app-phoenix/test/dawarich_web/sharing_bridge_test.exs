defmodule DawarichWeb.SharingBridgeTest do
  use ExUnit.Case, async: true

  test "family Turbo flash streams enter the initiating LiveView bridge" do
    run("""
    import assert from "node:assert/strict";
    import fs from "node:fs";
    import vm from "node:vm";
    const listeners = new Map();
    const context = vm.createContext({window: {}, document: {
      addEventListener: (name, callback) => listeners.set(name, callback),
      removeEventListener: name => listeners.delete(name)
    }});
    const dependency = new vm.SyntheticModule(["Application", "lazyLoadControllersFrom"], function() {
      this.setExport("Application", class {async start() {} register() {} stop() {}});
      this.setExport("lazyLoadControllersFrom", () => {});
    }, {context});
    await dependency.link(() => {});
    await dependency.evaluate();
    const module = new vm.SourceTextModule(fs.readFileSync("priv/static/js/rails_bridge.js", "utf8"), {
      context, importModuleDynamically: () => dependency
    });
    await module.link(() => {});
    await module.evaluate();
    const element = {
      addEventListener: (name, callback, capture) => assert.equal(capture, true), removeAttribute() {},
      getAttribute: () => "", querySelectorAll: () => []
    };
    const bridge = module.namespace.railsBridge(element);
    await bridge.ready;
    const content = {};
    let flashed = null;
    let prevented = false;
    bridge.flash = value => flashed = value;
    bridge.onSubmit({target: {closest: () => null}});
    const event = {target: {
      getAttribute: name => name === "action" ? "append" : "flash-messages",
      querySelector: () => ({content})
    }, preventDefault: () => prevented = true};
    listeners.get("turbo:before-stream-render")?.(event);
    assert.equal(flashed, content);
    assert.equal(prevented, true);
    """)
  end

  test "a consenting member hides the flex map placeholder and revocation reveals it" do
    run("""
    import assert from "node:assert/strict";
    import fs from "node:fs";
    import vm from "node:vm";
    const context = vm.createContext({AbortController});
    const dependency = new vm.SyntheticModule(["railsBridge"], function() {
      this.setExport("railsBridge", () => {});
    }, {context});
    await dependency.link(() => {});
    const module = new vm.SourceTextModule(fs.readFileSync("priv/static/js/family_page.js", "utf8"), {context});
    await module.link(() => dependency);
    await module.evaluate();
    const classes = new Set(["flex"]);
    const empty = {classList: {toggle: (name, on) => on ? classes.add(name) : classes.delete(name)}};
    const controller = {disconnect() {}, async initMap() {}};
    const locations = [{user_id: 1}];
    const hook = module.namespace.familyPage({
      fetch: async () => ({ok: true, json: async () => locations}),
      controller: async () => controller
    });
    hook.el = {addEventListener() {}, querySelectorAll: () => [], querySelector: () => empty};
    await hook.mounted();
    assert.equal(classes.has("hidden"), true);
    assert.equal(controller.locationsValue, locations);
    hook.clear();
    assert.equal(classes.has("hidden"), false);
    """)
  end

  defp run(script) do
    {output, status} =
      System.cmd("node", ["--experimental-vm-modules", "--input-type=module", "-e", script],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  test "sharing controls wait for Stimulus handlers and retain initially disabled fields" do
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

  test "a Rails sharing flash received before LiveView joins survives the connection" do
    run("""
    import assert from "node:assert/strict";
    import fs from "node:fs";
    import vm from "node:vm";
    const context = vm.createContext({window: {}, document: {
      addEventListener() {}, getElementById: () => ({appendChild() {}})
    }});
    const dependency = new vm.SyntheticModule(["Application", "lazyLoadControllersFrom"], function() {
      this.setExport("Application", class {async start() {} register() {} stop() {}});
      this.setExport("lazyLoadControllersFrom", () => {});
    }, {context});
    await dependency.link(() => {});
    await dependency.evaluate();
    const module = new vm.SourceTextModule(fs.readFileSync("priv/static/js/rails_bridge.js", "utf8"), {
      context, importModuleDynamically: () => dependency
    });
    await module.link(() => {});
    await module.evaluate();
    const element = {addEventListener() {}, removeAttribute() {}, getAttribute: () => "", querySelectorAll: () => []};
    const alert = {classList: {contains: () => false},
      querySelector: () => ({textContent: "Location sharing enabled"})};
    const content = {querySelector: () => alert, querySelectorAll: () => [alert], cloneNode: () => content};
    const bridge = module.namespace.railsBridge(element);
    await bridge.ready;
    bridge.flash(content);
    const messages = [];
    const hook = {el: element, pushEvent: (event, params) => messages.push([event, params.message])};
    hook.reconnected = () => module.namespace.RailsStimulus.reconnected.call(hook);
    module.namespace.RailsStimulus.mounted.call(hook);
    assert.deepEqual(messages, [["rails_flash", "Location sharing enabled"]]);
    hook.reconnected();
    assert.equal(messages.length, 1);
    """)
  end
end
