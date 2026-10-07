defmodule Dawarich.FamilyApi.Closure do
  @moduledoc false
  alias Dawarich.{I18n, RailsTime, Repo}
  alias Dawarich.AccountApi.Closure, as: Account
  alias Dawarich.Families.{Clock, History, Locations, Mine, Requests, Sharing, SharingUpdate}
  alias DawarichWeb.Api.Params

  def run(action, user, params, now) do
    case Account.pending(user, now) do
      :ok -> gate(action, user, params, now)
      pending -> pending
    end
  rescue
    _ -> {:ok, 500, error("internal_server_error")}
  end

  defp gate(action, user, params, now) do
    [_settings, family] = Locations.membership(user.id)
    entitled = Account.family?(user, now)

    cond do
      action == :mine and family != nil and not entitled ->
        lapsed(user, family)

      not entitled ->
        {:ok, 403,
         {:object,
          [
            {"error", "family_plan_required"},
            {"message", I18n.en!("controllers.application.family_plan_required")},
            {"upgrade_url", Account.upgrade_url(user, now)}
          ]}}

      family == nil ->
        {:ok, 404, Locations.not_in_family()}

      true ->
        terminal(dispatch(action, user, params, now))
    end
  end

  defp lapsed(user, family) do
    [[name, role]] =
      Repo.query!(
        "SELECT f.name,m.role FROM families f JOIN family_memberships m ON m.family_id=f.id WHERE f.id=$1 AND m.user_id=$2",
        [family, user.id]
      ).rows

    {:ok, 200,
     {:object,
      [
        {"lapsed", true},
        {"family", {:object, [{"name", name}]}},
        {"me", {:object, [{"user_id", user.id}, {"owner", role == 0}]}}
      ]}}
  end

  defp dispatch(:locations, user, _params, now), do: Locations.read(user, now)
  defp dispatch(:mine, user, _params, now), do: Mine.read(user, now)
  defp dispatch(:sharing, user, params, now), do: SharingUpdate.call(user, params, now)
  defp dispatch(:create, user, params, now), do: Requests.create(user, params, now)

  defp dispatch(decision, user, params, now) when decision in [:accept, :decline],
    do: Requests.respond(user, decision, params, now)

  defp dispatch(:history, user, params, now) do
    if params["start_at"] in [nil, ""] or params["end_at"] in [nil, ""] do
      {:ok, 400,
       error(I18n.en!("controllers.api.v1.families.locations.start_at_and_end_at_are_required"))}
    else
      with {:ok, {:text, from}} <- Params.timestamp(params["start_at"]),
           {:ok, {:text, to}} <- Params.timestamp(params["end_at"]) do
        [_settings, family] = Locations.membership(user.id)

        RailsTime.with_zone(Account.zone(user.timezone), fn ->
          members =
            for member <- Locations.members(family),
                member.id != user.id,
                Sharing.enabled?(Dawarich.UserSettings.get(member), now),
                do: member

          {:ok, 200,
           {:object, [{"members", Enum.flat_map(members, &history(&1, from, to, now))}]}}
        end)
      else
        _ ->
          {:ok, 400, error(I18n.en!("controllers.api.v1.families.locations.invalid_date_format"))}
      end
    end
  end

  defp history(member, from, to, now) do
    config = Sharing.config(Dawarich.UserSettings.get(member))
    started = Clock.parse(config["started_at"])
    before = config["history_before_sharing"] == true

    if config["share_history"] == true and (started != nil or before) do
      window =
        Map.get(
          %{"24h" => "24 hours", "7d" => "7 days", "30d" => "30 days", "all" => "1 year"},
          config["history_window"] || "7d",
          "7 days"
        )

      points =
        Repo.query!(History.points_sql(), [member.id, from, to, now, window, started, before]).rows

      if points == [],
        do: [],
        else: [
          {:object,
           [
             {"user_id", member.id},
             {"email", member.email},
             {"name", member.name},
             {"email_initial", Locations.initial(member.email)},
             {"sharing_since", Clock.iso(started)},
             {"points", points}
           ]}
        ]
    else
      []
    end
  end

  defp terminal({:replay, _}), do: {:ok, 500, error("internal_server_error")}
  defp terminal(result), do: result
  defp error(message), do: {:object, [{"error", message}]}
end
