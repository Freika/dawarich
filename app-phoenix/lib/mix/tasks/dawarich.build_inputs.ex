defmodule Mix.Tasks.Dawarich.BuildInputs do
  @moduledoc false
  use Mix.Task

  alias Dawarich.Build
  alias Dawarich.Build.Sprockets.{Compiler, Writer}

  @impl true
  def run(args) do
    {opts, []} = OptionParser.parse!(args, strict: [root: :string, out: :string])
    root = opts |> Keyword.fetch!(:root) |> Path.expand()
    out = opts |> Keyword.fetch!(:out) |> Path.expand()
    assets = Writer.write!(out, Compiler.compile(root), Writer.now())
    i18n = root |> Build.I18n.export() |> IO.iodata_to_binary()
    phoenix = Path.join(out, "tmp/phoenix")

    Build.write!(Path.join(phoenix, "i18n.json"), i18n)

    Build.write!(
      Path.join(phoenix, "achievements.json"),
      Build.Achievements.export(root, Jason.decode!(i18n))
    )

    Build.write!(Path.join(phoenix, "importmap.json"), Build.Importmap.export(root, assets))
  end
end
