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

  test "reports controllers and hooks set through conditional expressions", %{tmp_dir: root} do
    write!(root, "lib/dawarich_web/shell.ex", """
    <div data-controller={!@native && "removals"} phx-hook={assigns[:native] && "Dismissible"}>
    <ul data-controller={if @native, do: nil, else: "notifications clipboard"}>
    """)

    assert FrontendInventory.scan(root) == [
             %{file: "lib/dawarich_web/shell.ex", kind: :hook, value: "Dismissible"},
             %{file: "lib/dawarich_web/shell.ex", kind: :stimulus, value: "clipboard"},
             %{file: "lib/dawarich_web/shell.ex", kind: :stimulus, value: "notifications"},
             %{file: "lib/dawarich_web/shell.ex", kind: :stimulus, value: "removals"}
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

  test "hotwire?/1 is true for Turbo, Stimulus and ActionCable findings" do
    assert FrontendInventory.hotwire?(%{kind: :stimulus, value: "a"})
    assert FrontendInventory.hotwire?(%{kind: :hook, value: "RailsStimulus"})
    assert FrontendInventory.hotwire?(%{kind: :turbo, value: "turbo-frame"})
    refute FrontendInventory.hotwire?(%{kind: :hook, value: "EmojiPicker"})
    refute FrontendInventory.hotwire?(%{kind: :live_session, value: "native_pages"})
  end

  test "native graph distinguishes direct-upload adapters from Hotwire runtime", %{tmp_dir: root} do
    write!(root, "lib/dawarich_web/upload.ex", ~s|post "/direct_uploads", Upload, :create|)
    [adapter] = FrontendInventory.scan(root)
    refute FrontendInventory.hotwire?(adapter)

    metadata = %{
      "inputs" => %{
        "js/app.js" => %{
          "imports" => [
            %{"path" => "js/uploaders/direct.js", "kind" => "import-statement"},
            %{"path" => "@hotwired/turbo", "kind" => "import-statement", "external" => true}
          ]
        },
        "js/uploaders/direct.js" => %{"imports" => []}
      }
    }

    graph = apply(FrontendInventory, :graph, [metadata, ["js/app.js"]])
    assert Enum.any?(graph, &(&1.value == "js/uploaders/direct.js"))
    forbidden = Enum.filter(graph, &FrontendInventory.hotwire?/1)
    assert Enum.map(forbidden, & &1.value) == ["@hotwired/turbo"]
  end

  test "dynamic legacy import edge cannot evade the graph audit" do
    metadata = %{
      "inputs" => %{
        "js/app.js" => %{"imports" => [%{"path" => "js/lazy.js", "kind" => "dynamic-import"}]},
        "js/lazy.js" => %{
          "imports" => [
            %{"path" => "js/app.js", "kind" => "import-statement"},
            %{"path" => "@hotwired/stimulus", "kind" => "dynamic-import", "external" => true}
          ]
        },
        "test/negative.js" => %{
          "imports" => [
            %{"path" => "@rails/actiontext", "kind" => "import-statement", "external" => true}
          ]
        }
      }
    }

    graph = apply(FrontendInventory, :graph, [metadata, ["js/app.js"]])

    assert %{
             file: "js/lazy.js",
             kind: :module,
             value: "@hotwired/stimulus",
             import_kind: "dynamic-import"
           } in graph

    assert graph |> Enum.filter(&FrontendInventory.hotwire?/1) |> Enum.map(& &1.value) ==
             ["@hotwired/stimulus"]

    refute Enum.any?(graph, &(&1.file == "test/negative.js"))
  end
end
