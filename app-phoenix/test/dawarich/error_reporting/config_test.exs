defmodule Dawarich.ErrorReporting.ConfigTest do
  use ExUnit.Case, async: true

  test "Rails DSN and environment inputs configure error reporting without mandatory analytics" do
    env = %{
      "SENTRY_DSN" => "https://public@glitchtip.example.invalid/1",
      "RAILS_ENV" => "production"
    }

    config = Dawarich.ErrorReporting.Config.from_env(env, :prod)
    assert config[:dsn] == env["SENTRY_DSN"]
    assert config[:environment_name] == "production"
    assert config[:enable_logs] == false
    assert config[:traces_sample_rate] == 0.05
    assert config[:profiles_sample_rate] == 0.1
    assert config[:json_library] == Jason
    assert config[:client] == Dawarich.ErrorReporting.HttpClient
    assert Dawarich.ErrorReporting.Config.from_env(%{}, :prod)[:dsn] == nil

    assert Dawarich.ErrorReporting.Config.from_env(%{"SENTRY_ENVIRONMENT" => "staging"}, :prod)[
             :environment_name
           ] == "staging"

    assert Dawarich.ErrorReporting.Config.from_env(%{}, :prod)[:environment_name] == "development"

    assert Dawarich.ErrorReporting.Config.from_env(
             %{"SENTRY_CURRENT_ENV" => "current", "SENTRY_ENVIRONMENT" => "other"},
             :prod
           )[:environment_name] == "current"

    assert Dawarich.ErrorReporting.Config.from_env(%{"RACK_ENV" => "preview"}, :prod)[
             :environment_name
           ] == "preview"

    custom =
      Dawarich.ErrorReporting.Config.from_env(
        Map.merge(env, %{
          "SENTRY_ENABLE_LOGS" => "TrUe",
          "SENTRY_TRACES_SAMPLE_RATE" => "0.2",
          "SENTRY_PROFILES_SAMPLE_RATE" => "0.3"
        }),
        :prod
      )

    assert custom[:enable_logs]
    assert custom[:traces_sample_rate] == 0.2
    assert custom[:profiles_sample_rate] == 0.3
  end
end
