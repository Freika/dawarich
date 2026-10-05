defmodule DawarichWeb.MethodLinksTest do
  use ExUnit.Case, async: true

  test "GET method links navigate to the original URL and target without posting a form" do
    script = File.read!("priv/static/js/app.js")
    [_, function] = Regex.run(~r/const submitMethodLink = (.*?\n})\n\ndocument/s, script)

    code = """
    const assert = require("node:assert/strict")
    const navigations = []
    global.window = {open: (...args) => navigations.push(args)}
    global.document = {createElement: () => {throw new Error("GET created a POST form")}}
    global.meta = () => null
    const submitMethodLink = #{function}
    submitMethodLink({href: "https://example.invalid/export?format=zip", target: ""}, "get")
    submitMethodLink({href: "https://example.invalid/points?page=2", target: "reports"}, "GET")
    assert.deepEqual(navigations, [
      ["https://example.invalid/export?format=zip", "_self"],
      ["https://example.invalid/points?page=2", "reports"]
    ])
    """

    {output, status} = System.cmd("node", ["-e", code], stderr_to_stdout: true)
    assert status == 0, output
  end
end
