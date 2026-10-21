defmodule Dawarich.Admin.GeocodingTest do
  @moduledoc false
  alias Dawarich.Geocoding.{Config, Result, Search}
  alias Dawarich.I18n

  def call(repo, context) do
    config = Config.resolve(repo, Map.get(context, :env, System.get_env()))

    if config.enabled do
      search = Map.get(context, :provider_test, &Search.reverse/3)

      case search.(config, {51.3402, 12.3712}, limit: 1, max_wait: 5) do
        {:ok, [result | _]} ->
          place =
            [Result.city(config.provider, result), Result.country(config.provider, result)]
            |> Enum.reject(&(is_nil(&1) or &1 == ""))
            |> Enum.join(", ")

          message(context, :notice, "success", %{"place" => place})

        {:ok, []} ->
          message(context, :alert, "empty")

        nil ->
          message(context, :alert, "rate_limited")

        {:error, _} ->
          message(context, :alert, "failure", %{"error" => "Geocoding::Error"})
      end
    else
      message(context, :alert, "not_configured")
    end
  rescue
    _ -> message(context, :alert, "failure", %{"error" => "Geocoding::Error"})
  end

  defp message(context, kind, key, bindings \\ %{}) do
    {:ok, message} = I18n.t(context.locale, "admin.settings.test_geocoding." <> key, bindings)
    {:ok, kind, message}
  end
end
