defmodule Dawarich.Settings.Mobile do
  @moduledoc false
  alias Dawarich.{RubyInteger, UserSettings}
  alias Dawarich.Settings.Api

  @booleans ~w(tracking_visits track_visits_independently auto_start show_background_location_indicator upload_automatically upload_all_on_tracking_stop)
  @clamps %{
    "distance_filter" => 10000,
    "time_filter" => 3600,
    "track_break" => 1440,
    "accuracy" => 6,
    "batch_size" => 1000
  }

  def show(repo, user, ctx) do
    with :ok <- Api.guard(user, ctx), do: {:ok, 200, response(Api.read(repo, user.id))}
  rescue
    _ -> {:error, 500, Api.failure()}
  end

  def update(repo, user, params, ctx) do
    with :ok <- Api.guard(user, ctx, true),
         {:ok, raw} <- Dawarich.Points.ApiWrites.required(params, "settings") do
      sanitized = sanitize(raw)

      {:ok, settings} =
        repo.transaction(fn ->
          [[settings]] =
            repo.query!("SELECT settings FROM users WHERE id=$1 FOR UPDATE", [user.id],
              log: false
            ).rows

          mobile =
            Map.merge(settings["mobile"] || %{}, sanitized)
            |> Map.put(
              "updated_at",
              timestamp(repo, settings, ctx.now)
            )

          settings = Map.put(settings, "mobile", mobile)

          repo.query!(
            "UPDATE users SET settings=$2,updated_at=$3 WHERE id=$1",
            [user.id, settings, DateTime.to_naive(ctx.now)],
            log: false
          )

          settings
        end)

      Map.get(ctx, :after_commit, fn -> :ok end).()

      {:ok, 200,
       Map.put(
         response(settings),
         "message",
         Dawarich.I18n.en!("controllers.api.v1.settings.mobile.settings_updated")
       )}
    end
  rescue
    _ -> {:error, 500, Api.failure()}
  end

  defp timestamp(_repo, settings, now) do
    Dawarich.RailsTimeZone.format(now, settings, 0)
  end

  defp sanitize(raw) do
    sanitized =
      if raw["tracking_mode"] in ~w(precise significant),
        do: %{"tracking_mode" => raw["tracking_mode"]},
        else: %{}

    sanitized =
      Enum.reduce(@clamps, sanitized, fn {key, high}, acc ->
        if present?(raw[key]),
          do: Map.put(acc, key, min(max(RubyInteger.to_i(raw[key]), 1), high)),
          else: acc
      end)

    Enum.reduce(@booleans, sanitized, fn key, acc ->
      if present?(raw[key]), do: Map.put(acc, key, UserSettings.cast(raw[key])), else: acc
    end)
  end

  defp present?(value),
    do:
      not is_nil(value) and Dawarich.Ingest.Ruby.scalar?(value) and
        String.trim(Dawarich.Ingest.Ruby.to_s(value)) != ""

  defp response(settings) do
    mobile = settings["mobile"] || %{}

    %{
      "settings" => Map.delete(mobile, "updated_at"),
      "updated_at" => mobile["updated_at"],
      "capabilities" => %{"photo_library_import" => %{"version" => 1}},
      "status" => "success"
    }
  end
end
