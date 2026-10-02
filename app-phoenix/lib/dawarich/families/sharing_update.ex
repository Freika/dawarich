defmodule Dawarich.Families.SharingUpdate do
  @moduledoc false

  alias Dawarich.{I18n, RailsTime, Repo}
  alias Dawarich.Families.{Clock, Locations}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @false_values [false, "0", "f", "F", "false", "FALSE", "off", "OFF"]
  @hours %{"1h" => 1, "6h" => 6, "12h" => 12, "24h" => 24}
  @windows ~w(24h 7d 30d all)
  @strip ~r/\A[\0\t\n\v\f\r ]|[\0\t\n\v\f\r ]\z/

  def call(user, params, now) do
    case Locations.membership(user.id) do
      [_settings, nil] ->
        {:ok, 404, Locations.not_in_family()}

      [_settings, _family_id] ->
        if missing?(params["enabled"]),
          do: {:ok, 400, missing()},
          else: RailsTime.with_zone(user.timezone, fn -> update(user.id, params, now) end)
    end
  end

  def enable!(user_id, duration, now) when is_binary(duration),
    do: write!(user_id, %{"enabled" => true, "duration" => duration}, now)

  defp update(user_id, params, now) do
    enabled = boolean(params["enabled"])
    duration = duration(params["duration"])
    config = write!(user_id, Map.put(params, "enabled", enabled), now)
    expires = if enabled, do: Clock.parse(config["expires_at"])

    {:ok, 200,
     {:object,
      [
        {"success", true},
        {"enabled", enabled},
        {"duration", config["duration"] || "permanent"},
        {"message", message(enabled, duration)}
      ] ++
        if(expires,
          do: [{"expires_at", Clock.iso(expires)}, {"expires_at_formatted", formatted(expires)}],
          else: []
        )}}
  end

  defp write!(user_id, params, now) do
    [[settings, email]] =
      Repo.query!("SELECT settings, email FROM users WHERE id = $1", [user_id]).rows

    if Ruby.blank?(email), do: raise(ArgumentError, "a blank email fails Rails' validation")
    plain!(settings)
    family = settings["family"]
    unless is_nil(family) or is_map(family), do: raise(ArgumentError, "family settings")
    config = if params["enabled"], do: enabled(family, params, now), else: %{"enabled" => false}
    updated = Map.put(settings, "family", Map.put(family || %{}, "location_sharing", config))

    if updated != settings do
      Repo.query!("UPDATE users SET settings = $1, updated_at = $2 WHERE id = $3", [
        updated,
        Clock.naive(now),
        user_id
      ])
    end

    config
  end

  defp enabled(family, params, now) do
    old =
      case family && family["location_sharing"] do
        nil -> %{}
        %{} = old -> old
        _other -> raise ArgumentError, "sharing settings"
      end

    history = flag(params["share_history"])
    history = if is_nil(history), do: old["share_history"] || false, else: history
    consent = flag(params["history_before_sharing"])
    consent = if is_nil(consent), do: old["history_before_sharing"] == true, else: consent == true
    window = window(params["history_window"]) || old["history_window"]

    base = %{
      "enabled" => true,
      "started_at" => old["started_at"] || Clock.iso(Clock.naive(now)),
      "share_history" => history,
      "history_window" => if(window in @windows, do: window, else: "7d"),
      "history_before_sharing" => if(history in [nil, false], do: history, else: consent)
    }

    duration = duration(params["duration"])

    cond do
      Ruby.present?(duration) ->
        expiring(base, duration, expiry(duration, now))

      Ruby.present?(old["duration"]) ->
        existing = duration(old["duration"])
        expiring(base, existing, carried(existing, old["expires_at"], now))

      true ->
        base
    end
  end

  defp expiring(base, duration, nil), do: Map.put(base, "duration", duration)

  defp expiring(base, duration, at),
    do: base |> Map.put("duration", duration) |> Map.put("expires_at", Clock.iso(at))

  defp carried(duration, expires_at, now) do
    cond do
      Ruby.blank?(expires_at) -> nil
      future?(Clock.parse(expires_at), now) -> Clock.parse(expires_at)
      true -> expiry(duration, now)
    end
  end

  defp future?(at, now), do: NaiveDateTime.compare(at, Clock.naive(now)) == :gt

  defp expiry(duration, now) do
    case Map.fetch(@hours, duration) do
      {:ok, hours} -> NaiveDateTime.add(Clock.naive(now), hours * 3600)
      :error -> nil
    end
  end

  defp message(false, _duration), do: t("disabled", %{})

  defp message(true, duration) do
    case Map.fetch(@hours, duration) do
      {:ok, hours} -> t("enabled_for_hours", %{"count" => hours})
      :error -> t("enabled", %{})
    end
  end

  defp formatted(at) do
    [[text]] =
      Repo.query!(
        ~s|SELECT to_char($1::timestamp AT TIME ZONE 'UTC', 'Mon DD "at" HH12:MI AM')|,
        [at]
      ).rows

    text
  end

  defp missing?(value), do: value != false and Ruby.blank?(value)

  defp boolean(value) when is_binary(value) or is_boolean(value), do: value not in @false_values
  defp boolean(_value), do: raise(ArgumentError, "enabled parameter shape")

  defp flag(nil), do: nil
  defp flag(""), do: nil
  defp flag(value), do: boolean(value)

  defp window(value) when is_nil(value) or is_binary(value) or is_boolean(value), do: value
  defp window(_value), do: raise(ArgumentError, "history window parameter shape")

  defp duration(nil), do: nil

  defp duration(value) when is_binary(value) do
    if Ruby.blank?(value) or value == "permanent" or Map.has_key?(@hours, value),
      do: value,
      else: raise(ArgumentError, "duration outside the fixed choices")
  end

  defp duration(_value), do: raise(ArgumentError, "duration parameter shape")

  defp plain!(%{} = settings) do
    for key <- ~w(immich_url photoprism_url), not untouched_url?(settings[key]) do
      raise ArgumentError, "#{key} would be rewritten on save"
    end

    case settings["maps"] do
      nil ->
        :ok

      %{"url" => url} when is_binary(url) ->
        if url =~ @strip, do: raise(ArgumentError, "maps url")

      %{} ->
        :ok

      _other ->
        raise ArgumentError, "maps settings would be read on save"
    end
  end

  defp plain!(_settings), do: raise(ArgumentError, "settings are not an object")

  defp untouched_url?(url),
    do: is_nil(url) or (is_binary(url) and not String.ends_with?(url, "/"))

  defp missing do
    key = "controllers.api.v1.families.sharing.missing_required_parameter_param"
    {:ok, text} = I18n.t("en", key, %{"parameter" => "enabled"})
    {:object, [{"error", text}]}
  end

  defp t(key, bindings) do
    {:ok, text} = I18n.t("en", "services.families.update_location_sharing." <> key, bindings)
    text
  end
end
