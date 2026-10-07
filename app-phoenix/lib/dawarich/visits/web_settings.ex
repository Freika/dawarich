defmodule Dawarich.Visits.WebSettings do
  @moduledoc false
  alias Dawarich.{Entitlements, Repo, TimeZoneName, UserTimeZone}
  alias Dawarich.Visits.Settings

  def save(repo, user_id, %{} = params, now) do
    allowed =
      Map.take(params, ~w(visit_radius_meters visit_min_points visit_min_duration_minutes))

    if Enum.all?(allowed, fn {_key, value} -> scalar?(value) end) do
      changes = Map.new(allowed, fn {key, value} -> {key, Dawarich.RubyInteger.to_i(value)} end)

      transact(repo, user_id, fn %{settings: settings} ->
        merged = Map.merge(settings, changes)

        repo.query!(
          "UPDATE users SET settings=$2, updated_at=$3 WHERE id=$1",
          [user_id, merged, DateTime.to_naive(now)],
          log: false
        )

        merged
      end)
    else
      {:replay, "visit settings shape"}
    end
  end

  def save(_repo, _user_id, _params, _now), do: {:replay, "visit settings shape"}

  def redetect(repo, user_id, now, locale) do
    transact(repo, user_id, fn %{settings: settings, last_redetected: last} ->
      opts = if Dawarich.Standalone.enabled?(), do: [owner: :oban], else: []
      Dawarich.Visits.HistoryRedetect.enqueue(repo, user_id, settings, last, now, locale, opts)
    end)
  end

  defp transact(repo, user_id, fun) do
    case repo.transaction(fn ->
           case repo.query!(
                  "SELECT settings, visits_redetected_at FROM users WHERE id=$1 FOR UPDATE",
                  [user_id],
                  log: false
                ).rows do
             [[settings, last]] when is_map(settings) or is_nil(settings) ->
               fun.(%{settings: Dawarich.UserSettings.provided(settings), last_redetected: last})

             _ ->
               repo.rollback({:replay, "visit settings user"})
           end
         end) do
      {:ok, result} -> {:ok, result}
      {:error, result} -> result
    end
  end

  defp scalar?(value) when is_binary(value), do: String.valid?(value)
  defp scalar?(value), do: is_number(value) or is_boolean(value) or is_nil(value)

  def load(repo, user_id) do
    case repo.query!("SELECT settings, visits_redetected_at FROM users WHERE id = $1", [user_id],
           log: false
         ).rows do
      [[settings, last]] ->
        %{settings: Dawarich.UserSettings.provided(settings), last_redetected: last}

      [] ->
        nil
    end
  end

  def page(user, %{settings: %{} = settings, last_redetected: last}, now, self_hosted) do
    if valid_zone?(settings) do
      cooldown =
        not is_nil(last) and
          NaiveDateTime.compare(last, DateTime.to_naive(DateTime.add(now, -3600))) == :gt

      %{
        policy: Settings.policy(settings),
        cooldown: cooldown,
        available_at:
          if(cooldown,
            do:
              DawarichWeb.LocalizedTime.l(
                "en",
                UserTimeZone.local(settings, NaiveDateTime.add(last, 3600)).local,
                "short"
              )
          ),
        restricted: not Entitlements.full_access?(user, self_hosted, now),
        page_title:
          DawarichWeb.Translate.t(
            settings["locale"] || "en",
            "settings.visits.show.visit_detection",
            %{}
          ),
        rails_js: true,
        two_factor: DawarichWeb.SettingsParts.two_factor_available?()
      }
    else
      :rails
    end
  end

  def page(_user, _snapshot, _now, _self_hosted), do: :rails

  defp valid_zone?(settings) do
    zone = settings["timezone"] || UserTimeZone.zone(%{})

    is_binary(zone) and
      Repo.query!("SELECT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = $1)", [
        TimeZoneName.to_iana(zone)
      ]).rows == [[true]]
  end
end
