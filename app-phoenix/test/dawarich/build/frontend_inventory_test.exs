defmodule Dawarich.Build.FrontendInventoryTest do
  use ExUnit.Case, async: true

  alias Dawarich.Build.FrontendInventory

  @moduletag :tmp_dir

  defp write!(root, path, content) do
    file = Path.join(root, path)
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, content)
  end

  test "reports Hotwire dependencies and markup assertions per file", %{tmp_dir: root} do
    write!(root, "lib/dawarich_web/page.ex", """
    ~H\"\"\"
    <div data-controller="map-panel clipboard" phx-hook="RailsStimulus">
      <a data-turbo-method="delete" href="/x">x</a>
      <turbo-frame id="family"></turbo-frame>
    </div>
    \"\"\"
    """)

    write!(root, "lib/dawarich_web/router.ex", "live_session :native_pages, on_mount: []")
    write!(root, "priv/static/js/cable.js", "const c = createConsumer('/cable')")

    write!(root, "test/page_test.exs", """
    assert html |> LazyHTML.from_fragment() |> LazyHTML.query(".btn.btn-primary") != []
    assert html =~ "visible text"
    """)

    assert FrontendInventory.scan(root) == [
             %{file: "lib/dawarich_web/page.ex", kind: :hook, value: "RailsStimulus"},
             %{file: "lib/dawarich_web/page.ex", kind: :stimulus, value: "clipboard"},
             %{file: "lib/dawarich_web/page.ex", kind: :stimulus, value: "map-panel"},
             %{file: "lib/dawarich_web/page.ex", kind: :turbo, value: "data-turbo-method"},
             %{file: "lib/dawarich_web/page.ex", kind: :turbo, value: "turbo-frame"},
             %{file: "lib/dawarich_web/router.ex", kind: :live_session, value: "native_pages"},
             %{file: "priv/static/js/cable.js", kind: :action_cable, value: "createConsumer"},
             %{file: "test/page_test.exs", kind: :markup_assertion, value: ".btn.btn-primary"}
           ]
  end

  test "finds nothing in Hotwire-free sources", %{tmp_dir: root} do
    write!(
      root,
      "lib/dawarich_web/native.ex",
      ~s|<button phx-click="save" phx-hook="EmojiPicker">|
    )

    write!(root, "test/native_test.exs", ~s|assert render(view) =~ "Saved"|)

    assert FrontendInventory.scan(root) == [
             %{file: "lib/dawarich_web/native.ex", kind: :hook, value: "EmojiPicker"}
           ]
  end

  test "hotwire?/1 is true only for Turbo, Stimulus, ActionCable and direct-upload findings" do
    assert FrontendInventory.hotwire?(%{kind: :stimulus, value: "a"})
    assert FrontendInventory.hotwire?(%{kind: :hook, value: "RailsStimulus"})
    assert FrontendInventory.hotwire?(%{kind: :turbo, value: "turbo-frame"})
    refute FrontendInventory.hotwire?(%{kind: :hook, value: "EmojiPicker"})
    refute FrontendInventory.hotwire?(%{kind: :live_session, value: "native_pages"})
  end
end
