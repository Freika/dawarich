defmodule Dawarich.Families.Mine do
  @moduledoc false

  alias Dawarich.{RailsTime, Repo}
  alias Dawarich.Families.{Clock, Locations, Sharing}

  def read(user, now) do
    case Locations.membership(user.id) do
      [_settings, nil] ->
        {:ok, 404, Locations.not_in_family()}

      [settings, family_id] ->
        RailsTime.with_zone(user.timezone, fn ->
          {:ok, 200, payload(user.id, settings, family_id, now)}
        end)
    end
  end

  defp payload(user_id, settings, family_id, now) do
    members = Locations.members(family_id)
    [[name]] = Repo.query!("SELECT name FROM families WHERE id = $1", [family_id]).rows

    {:object,
     [
       {"lapsed", false},
       {"history_before_sharing_supported", true},
       {"family", {:object, [{"name", name}]}},
       {"me", me(user_id, settings, members, now)},
       {"members", Enum.map(members, &member(&1, now))},
       {"location_requests", requests(user_id, now)}
     ]}
  end

  defp me(user_id, settings, members, now) do
    config = Sharing.config(settings) || %{}

    {:object,
     [
       {"user_id", user_id},
       {"owner", Enum.any?(members, &(&1.id == user_id and &1.role == 0))},
       {"sharing",
        {:object,
         [
           {"enabled", Sharing.enabled?(settings, now)},
           {"duration", config["duration"] || "permanent"},
           {"expires_at", config["expires_at"] |> Clock.parse() |> Clock.iso()},
           {"started_at", config["started_at"] |> Clock.parse() |> Clock.iso()},
           {"share_history", config["share_history"] == true},
           {"history_window", config["history_window"] || "7d"},
           {"history_before_sharing", config["history_before_sharing"] == true}
         ]}}
     ]}
  end

  defp member(member, now) do
    config = Sharing.config(Dawarich.UserSettings.get(member)) || %{}

    shared =
      Sharing.enabled?(Dawarich.UserSettings.get(member), now) and config["share_history"] == true

    {:object,
     [
       {"user_id", member.id},
       {"email", member.email},
       {"name", member.name},
       {"email_initial", Locations.initial(member.email)},
       {"owner", member.role == 0},
       {"sharing_enabled", Sharing.enabled?(Dawarich.UserSettings.get(member), now)},
       {"share_history", shared},
       {"history_window", if(shared, do: config["history_window"] || "7d")},
       {"history_before_sharing", config["history_before_sharing"] == true},
       {"sharing_started_at", config["started_at"] |> Clock.parse() |> Clock.iso()},
       {"joined_at", Clock.iso(member.joined)}
     ]}
  end

  defp requests(user_id, now) do
    active = "status = 0 AND expires_at > $2"

    incoming =
      Repo.query!(
        "SELECT r.id, r.requester_id, u.email, r.suggested_duration, r.expires_at, r.created_at " <>
          "FROM family_location_requests r " <>
          "LEFT JOIN users u ON u.id = r.requester_id AND u.deleted_at IS NULL " <>
          "WHERE r.target_user_id = $1 AND r.#{active}",
        [user_id, Clock.naive(now)]
      ).rows

    outgoing =
      Repo.query!(
        "SELECT id, target_user_id, created_at FROM family_location_requests " <>
          "WHERE requester_id = $1 AND #{active}",
        [user_id, Clock.naive(now)]
      ).rows

    {:object,
     [
       {"incoming", Enum.map(incoming, &incoming/1)},
       {"outgoing",
        for [id, target, created] <- outgoing do
          {:object, [{"id", id}, {"target_user_id", target}, {"created_at", Clock.iso(created)}]}
        end}
     ]}
  end

  defp incoming([_id, _requester, nil | _rest]), do: raise(ArgumentError, "requester is gone")

  defp incoming([id, requester, email, duration, expires, created]) do
    {:object,
     [
       {"id", id},
       {"requester", {:object, [{"user_id", requester}, {"email", email}]}},
       {"suggested_duration", duration},
       {"expires_at", Clock.iso(expires)},
       {"created_at", Clock.iso(created)}
     ]}
  end
end
