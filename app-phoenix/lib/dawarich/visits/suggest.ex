defmodule Dawarich.Visits.Suggest do
  @moduledoc false

  require Logger

  alias Dawarich.Geocoding.Config
  alias Dawarich.Mail.ExploreFeatures
  alias Dawarich.{I18n, Notifications, RailsEffects, Redis}
  alias Dawarich.Visits.{Settings, SmartDetect, Sql}

  @known "SELECT floor(extract(epoch FROM started_at))::bigint, " <>
           "floor(extract(epoch FROM ended_at))::bigint FROM visits v WHERE #{Sql.machine("v")} " <>
           "AND v.user_id = $1 AND v.started_at <= $2 AND v.ended_at >= $3"
  @scope "services.visits.suggest."

  def run(repo, user_id, start, stop, args) do
    known = known(repo, user_id, start, stop)
    %{visits: visits} = SmartDetect.run(repo, user_id, start, stop, args)
    fresh_places = fresh_places(visits, known)

    if fresh_places != [] and Config.resolve(repo).enabled,
      do:
        repo.transaction(fn ->
          Enum.each(fresh_places, &RailsEffects.reverse_place(repo, user_id, &1))
        end)

    :ok
  rescue
    exception -> notify_error(repo, user_id, start, stop, exception)
  end

  defp known(repo, user_id, start, stop) do
    for [s, e] <- repo.query!(@known, [user_id, naive(stop), naive(start)], log: false).rows do
      {s, e}
    end
  end

  defp fresh_places(visits, known) do
    visits
    |> Enum.reject(fn v ->
      Enum.any?(known, fn {ks, ke} -> v.started_at < ke and v.ended_at > ks end)
    end)
    |> Enum.map(& &1.place_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp notify_error(repo, user_id, start, stop, exception) do
    Logger.error(
      "event=visits.suggest_error user_id=#{user_id} start=#{start} stop=#{stop} " <>
        "error=#{Exception.message(exception)}"
    )

    claim = Redis.command(["SET", "visit_suggest_error:user:#{user_id}", "1", "NX", "EX", "3600"])
    unless match?({:ok, nil}, claim), do: notify!(repo, user_id, exception)
    :ok
  end

  defp notify!(repo, user_id, exception) do
    locale = ExploreFeatures.locale(settings(repo, user_id), nil)
    {:ok, title} = I18n.t(locale, @scope <> "error_suggesting_visits")

    {:ok, content} =
      I18n.t(locale, @scope <> "error_suggesting_visits_message", %{
        "message" => Exception.message(exception)
      })

    Notifications.create!(repo, user_id, :error, title, content)
  end

  defp settings(repo, user_id) do
    case Settings.load(repo, user_id) do
      %{settings: settings} -> settings
      nil -> nil
    end
  end

  defp naive(seconds), do: seconds |> DateTime.from_unix!() |> DateTime.to_naive()
end
