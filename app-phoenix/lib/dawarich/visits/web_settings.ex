defmodule Dawarich.Visits.WebSettings do
  @moduledoc false
  alias Dawarich.{Entitlements, Repo, TimeZoneName, UserTimeZone}
  alias Dawarich.Visits.Settings

  def load(repo, user_id) do
    case repo.query!("SELECT settings, visits_redetected_at FROM users WHERE id = $1", [user_id],
           log: false
         ).rows do
      [[settings, last]] -> %{settings: settings, last_redetected: last}
      [] -> nil
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
