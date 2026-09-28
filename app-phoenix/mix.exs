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
    [mod: {Dawarich.Application, []}, extra_applications: [:logger, :inets, :ssl]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:oban, "~> 2.20"},
      {:jason, "~> 1.4"},
      {:phoenix, "~> 1.8.1"},
      {:phoenix_html, "~> 4.2"},
      {:phoenix_live_view, "~> 1.1"},
      {:lazy_html, "~> 0.1.0", only: :test},
      {:bandit, "~> 1.12"},
      {:gen_smtp, "~> 1.3"}
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
      test: [
        "app.config",
        fn _ -> Dawarich.Release.migrate_oban() end,
        "dawarich.i18n",
        "test"
      ]
    ]
  end
end
