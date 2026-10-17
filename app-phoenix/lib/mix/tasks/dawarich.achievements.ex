defmodule Mix.Tasks.Dawarich.Achievements do
  @moduledoc false
  use Mix.Task

  alias Dawarich.Build

  @impl true
  def run(_args) do
    Mix.Task.run("dawarich.i18n")
    root = Build.root()
    target = Application.fetch_env!(:dawarich, :achievements_path)

    Build.refresh!(target, root, fn ->
      translations =
        :dawarich |> Application.fetch_env!(:i18n_path) |> File.read!() |> Jason.decode!()

      Build.Achievements.export(root, translations)
    end)
  end
end
