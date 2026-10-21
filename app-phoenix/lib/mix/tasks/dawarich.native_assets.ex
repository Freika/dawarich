defmodule Mix.Tasks.Dawarich.NativeAssets do
  @moduledoc false
  use Mix.Task

  @impl true
  def run(args) do
    {opts, []} = OptionParser.parse!(args, strict: [root: :string, out: :string])
    root = opts |> Keyword.get(:root, Dawarich.RailsRoot.root()) |> Path.expand()
    out = opts |> Keyword.get(:out, "priv/static") |> Path.expand()
    Dawarich.Build.NativeAssets.build!(root, out)
  end
end
