defmodule Dawarich.MixProject do
  use Mix.Project

  def project do
    [
      app: :dawarich,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: [dawarich: [include_executables_for: [:unix], include_erts: false]]
    ]
  end

  def application do
    [mod: {Dawarich.Application, []}, extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:oban, "~> 2.20"},
      {:jason, "~> 1.4"}
    ]
  end

  defp aliases do
    [
      "ecto.migrate": ["app.config", fn _ -> Dawarich.Release.migrate() end],
      "ecto.drop": fn _ ->
        Mix.raise("Rails owns the Dawarich database; Phoenix never drops it")
      end,
      "ecto.reset": fn _ ->
        Mix.raise("Rails owns the Dawarich database; Phoenix never resets it")
      end,
      test: ["app.config", fn _ -> Dawarich.Release.migrate_oban() end, "test"]
    ]
  end
end
