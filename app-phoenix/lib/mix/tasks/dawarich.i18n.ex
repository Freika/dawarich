defmodule Mix.Tasks.Dawarich.I18n do
  @moduledoc false
  use Mix.Task

  @impl true
  def run(_args) do
    target = Application.fetch_env!(:dawarich, :i18n_path)
    sources = ["../Gemfile.lock" | Path.wildcard("../config/locales/**/*.yml")]

    if stale?(target, sources) do
      {_, 0} =
        System.cmd("bundle", ["exec", "rake", "phoenix:i18n[#{target}]"],
          cd: "..",
          env: [{"RAILS_ENV", "test"}],
          stderr_to_stdout: true,
          into: IO.stream()
        )
    end
  end

  defp stale?(target, sources) do
    case File.stat(target, time: :posix) do
      {:ok, %{mtime: built}} -> Enum.any?(sources, &(File.stat!(&1, time: :posix).mtime > built))
      {:error, _} -> true
    end
  end
end
