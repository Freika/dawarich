defmodule Mix.Tasks.Dawarich.I18n do
  @moduledoc false
  use Mix.Task

  alias Dawarich.Build

  @impl true
  def run(_args) do
    root = Build.root()
    target = Application.fetch_env!(:dawarich, :i18n_path)
    Build.refresh!(target, root, fn -> Build.I18n.export(root) end)
  end
end
