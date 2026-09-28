defmodule Mix.Tasks.Dawarich.Achievements do
  @moduledoc false
  use Mix.Task

  @impl true
  def run(_args) do
    target = Application.fetch_env!(:dawarich, :achievements_path)

    sources =
      [
        "../Gemfile.lock",
        "../config/achievements.yml",
        "../config/achievements/planet.yml",
        "../app/services/achievements/registry.rb",
        "../app/services/achievements/set_presenter.rb",
        "../lib/tasks/phoenix.rake"
      ] ++ Path.wildcard("../config/locales/**/*.yml")

    if Mix.Tasks.Dawarich.I18n.stale?(target, sources) do
      {_, 0} =
        System.cmd("bundle", ["exec", "rake", "phoenix:achievements[#{target}]"],
          cd: "..",
          env: [{"RAILS_ENV", "test"}],
          stderr_to_stdout: true,
          into: IO.stream()
        )
    end
  end
end
