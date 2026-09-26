import Config

env_integer = fn name, default ->
  case System.get_env(name) do
    value when value in [nil, ""] -> default
    value -> String.to_integer(value)
  end
end

if config_env() != :test do
  default_database =
    if config_env() == :prod, do: "dawarich_production", else: "dawarich_development"

  repo_config =
    case System.get_env("DATABASE_URL") do
      url when url in [nil, ""] ->
        [
          hostname: System.get_env("DATABASE_HOST", "localhost"),
          port: env_integer.("DATABASE_PORT", 5432),
          username: System.get_env("DATABASE_USERNAME"),
          password: System.get_env("DATABASE_PASSWORD"),
          database: System.get_env("DATABASE_NAME", default_database)
        ]

      url ->
        [url: String.replace(url, ~r{^postgis://}, "postgres://")]
    end

  config :dawarich, Dawarich.Repo, repo_config ++ [pool_size: 1]
end

case System.get_env("DAWARICH_RAILS_ARGS") do
  args when args in [nil, ""] ->
    :ok

  args ->
    config :dawarich,
           :rails_argv,
           args |> String.replace_suffix("\x1F", "") |> String.split("\x1F")
end
