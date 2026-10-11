defmodule Mix.Tasks.Dawarich.NativeGraph do
  @moduledoc false
  use Mix.Task

  @impl true
  def run(args) do
    {opts, []} = OptionParser.parse!(args, strict: [meta: :string, public: :string])
    meta = File.read!(Keyword.get(opts, :meta, "priv/static/native/meta.json")) |> Jason.decode!()
    public = Keyword.get(opts, :public, Dawarich.RailsRoot.join("public"))
    entries = ~w(js/app.js js/auth_http.js js/public_charts.js)

    case Dawarich.Build.NativeDependencyGraph.audit(meta, entries, "assets", public) do
      [] -> :ok
      findings -> Mix.raise("Forbidden native frontend dependencies: #{inspect(findings)}")
    end
  end
end
