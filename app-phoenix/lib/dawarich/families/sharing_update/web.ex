defmodule Dawarich.Families.SharingUpdate.Web do
  @moduledoc false
  alias Dawarich.{Repo, RailsTime, I18n}
  alias Dawarich.Families.{Locations, Clock, SharingUpdate}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @false_values [false, 0, "0", "f", "F", "false", "FALSE", "off", "OFF"]

  def call(user, params, now) do
    case Locations.membership(user.id) do
      [_settings, nil] ->
        {:ok, 404,
         {:object,
          [
            {"error",
             DawarichWeb.Translate.t(
               Map.get(user, :locale, "en"),
               "controllers.family.location_sharing.user_is_not_part_of_a_family",
               %{}
             )}
          ]}}

      [_settings, _family] ->
        enabled = boolean(params["enabled"])
        params = params |> Map.put("enabled", enabled) |> Map.put("web", true)

        config =
          RailsTime.with_zone(user.timezone, fn ->
            SharingUpdate.web_write!(user.id, params, now)
          end)

        RailsTime.with_zone(user.timezone, fn ->
          response(enabled, config, params["duration"], Map.get(user, :locale, "en"))
        end)
    end
  rescue
    _error ->
      {:ok, 500, {:object, [{"success", false}, {"message", message(user, "unexpected_error")}]}}
  end

  def boolean(value) when value in [nil, ""], do: nil
  def boolean(value), do: value not in @false_values

  def duration(value), do: if(Ruby.blank?(value), do: nil, else: value)

  def hours(nil), do: 0
  def hours("permanent"), do: 0

  def hours(value) when is_binary(value) do
    case Integer.parse(String.trim_leading(value)) do
      {n, _rest} -> max(0, n)
      :error -> 0
    end
  end

  def hours(value) when is_integer(value), do: max(0, value)
  def hours(_other), do: raise(ArgumentError, "duration cannot convert to integer")

  defp response(enabled, config, raw_duration, locale) do
    count = if enabled, do: hours(raw_duration), else: 0

    key =
      cond do
        not enabled -> "disabled"
        count > 0 -> "enabled_for_hours"
        true -> "enabled"
      end

    {:ok, message} =
      I18n.t(locale, "services.families.update_location_sharing." <> key, %{"count" => count})

    fields = [
      {"success", true},
      {"enabled", enabled},
      {"duration", config["duration"] || "permanent"},
      {"message", message}
    ]

    expires = if enabled, do: Clock.parse(config["expires_at"])

    fields =
      if expires do
        [[local]] =
          Repo.query!(
            "SELECT ($1::timestamp AT TIME ZONE 'UTC') AT TIME ZONE current_setting('TimeZone')",
            [expires]
          ).rows

        formatted = DawarichWeb.LocalizedDate.time(locale, local, "short_with_time")
        fields ++ [{"expires_at", Clock.iso(expires)}, {"expires_at_formatted", formatted}]
      else
        fields
      end

    {:ok, 200, {:object, fields}}
  end

  defp message(user, key) do
    {:ok, text} =
      I18n.t(Map.get(user, :locale, "en"), "services.families.update_location_sharing." <> key)

    text
  end
end
