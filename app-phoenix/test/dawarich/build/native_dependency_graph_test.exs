defmodule Dawarich.Build.NativeDependencyGraphTest do
  use ExUnit.Case, async: true
  alias Dawarich.Build.NativeDependencyGraph

  @moduletag :tmp_dir

  test "native lazy and worker import closures contain no Hotwire", %{tmp_dir: dir} do
    meta = Path.join(dir, "meta.json")

    assert Esbuild.install_and_run(:native, [
             "--minify",
             "--outdir=#{dir}",
             "--metafile=#{meta}",
             "--log-level=warning"
           ]) == 0

    graph = meta |> File.read!() |> Jason.decode!()
    entries = ~w(js/app.js js/auth_http.js js/public_charts.js)

    assert NativeDependencyGraph.audit(
             graph,
             entries,
             "assets",
             Dawarich.RailsRoot.join("public")
           ) == []

    source = Path.join(dir, "source")
    public = Path.join(dir, "public")
    File.mkdir_p!(Path.join(source, "js"))
    File.mkdir_p!(Path.join(public, "maplibre"))
    File.write!(Path.join(source, "js/app.js"), "import('./lazy.js')")
    File.write!(Path.join(source, "js/lazy.js"), "import('/maplibre/library.mjs')")

    File.write!(
      Path.join(public, "maplibre/library.mjs"),
      "new Worker(new URL('./worker.mjs', import.meta.url))"
    )

    worker = Path.join(public, "maplibre/worker.mjs")
    File.write!(worker, "self.postMessage('ready')")

    graph = %{
      "inputs" => %{
        "js/app.js" => %{"imports" => [%{"path" => "js/lazy.js", "kind" => "dynamic-import"}]},
        "js/lazy.js" => %{
          "imports" => [
            %{"path" => "/maplibre/library.mjs", "kind" => "dynamic-import", "external" => true}
          ]
        }
      }
    }

    assert NativeDependencyGraph.audit(graph, ["js/app.js"], source, public) == []
    File.write!(worker, "window.Turbo = {}; self.postMessage('ready')")

    assert [%{value: "window.Turbo"}] =
             NativeDependencyGraph.audit(graph, ["js/app.js"], source, public)
  end
end
