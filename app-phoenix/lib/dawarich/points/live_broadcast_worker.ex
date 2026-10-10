defmodule Dawarich.Points.LiveBroadcastWorker do
  @moduledoc false
  use Oban.Worker, queue: :projections, max_attempts: 10

  alias Dawarich.{Cable, State}
  alias Dawarich.Families.{Locations, Sharing}

  def args_from_command(
        1,
        %{"user_id" => user, "broadcast_id" => event, "upserted" => points, "payloads" => data} =
          payload
      )
      when is_integer(user) and is_list(points) and is_list(data) and map_size(payload) == 4 do
    with {:ok, _} <- Ecto.UUID.cast(event),
         true <- Enum.all?(points, &valid_point?/1),
         true <- Enum.all?(data, &(is_map(&1) and is_integer(&1["timestamp"]))) do
      {:ok, payload}
    else
      _ -> {:error, "invalid_payload"}
    end
  end

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  defp valid_point?(%{"id" => id, "timestamp" => stamp, "longitude" => lon, "latitude" => lat}),
    do: is_integer(id) and is_integer(stamp) and is_number(lon) and is_number(lat)

  defp valid_point?(_), do: false

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  def run(repo, %{"user_id" => user, "upserted" => points} = args, opts \\ []) do
    case repo.query!(
           "SELECT settings FROM users WHERE id=$1 AND deleted_at IS NULL",
           [user],
           log: false
         ).rows do
      [[settings]] when points != [] ->
        settings = Dawarich.UserSettings.safe(settings)

        Dawarich.AfterCommit.once(repo, args["broadcast_id"], fn ->
          if State.claim(repo, "live_broadcast:done:#{args["broadcast_id"]}", 86_400) do
            now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
            payloads = Map.new(args["payloads"], &{&1["timestamp"], &1})

            for point <- points do
              if Map.get(settings, "live_map_enabled", true) not in [nil, false],
                do: publish_point(repo, user, point, Map.get(payloads, point["timestamp"], %{}))
            end

            publish_family(repo, user, points, now, opts)
            publish_shares(repo, user, Enum.max_by(points, & &1["timestamp"]), now)
          end

          :ok
        end)

      _ ->
        :ok
    end
  end

  defp publish_point(repo, user, p, data) do
    message = [
      p["latitude"] * 1.0,
      p["longitude"] * 1.0,
      text(data["battery"]),
      text(data["altitude"]),
      text(p["timestamp"]),
      text(data["velocity"]),
      text(p["id"]),
      ""
    ]

    :ok = Cable.broadcast_to("points", {:user, user}, message, repo: repo)
  end

  defp family(repo, user, settings, now) do
    if Sharing.enabled?(settings, now) do
      case repo.query!(
             "SELECT f.id,f.access_until,o.plan,o.active_until FROM family_memberships m JOIN families f ON f.id=m.family_id LEFT JOIN users o ON o.id=f.creator_id AND o.deleted_at IS NULL WHERE m.user_id=$1",
             [user],
             log: false
           ).rows do
        [[id, access, plan, until]] ->
          if DawarichWeb.LayoutAssigns.self_hosted?() or
               Dawarich.Entitlements.inherited?(access, plan, until, now),
             do: id

        [] ->
          nil
      end
    end
  end

  defp publish_family(repo, user, points, now, opts) do
    actor = Dawarich.Families.Snapshot.actor(repo, user)

    result =
      if actor do
        Dawarich.Families.Snapshot.read(actor, Keyword.merge(opts, repo: repo, now: now), fn ->
          fresh = Dawarich.Families.Snapshot.actor(repo, user)
          settings = if fresh, do: Dawarich.UserSettings.get(fresh), else: %{}
          family = if fresh, do: family(repo, user, settings, now)

          {:ok,
           if(family, do: {family, Enum.map(points, &family_message(repo, fresh, settings, &1))})}
        end)
      end

    case result do
      {:ok, {family, messages}} ->
        for message <- messages,
            do:
              :ok = Cable.broadcast_to("family_locations", {:family, family}, message, repo: repo)

        Dawarich.Families.ProducerEvents.family(repo, family, :location, now)

      _ ->
        :ok
    end
  end

  defp family_message(repo, actor, settings, p) do
    at = DateTime.from_unix!(p["timestamp"])
    zone = Dawarich.UserTimeZone.iana(repo, settings)

    [[iso]] =
      Dawarich.RailsTime.with_zone(repo, zone, fn ->
        repo.query!(
          "SELECT " <> Dawarich.RailsTime.sql("$1::timestamp", 0),
          [DateTime.to_naive(at)],
          log: false
        ).rows
      end)

    %{
      "user_id" => actor.id,
      "email" => actor.email,
      "name" => Locations.display_name(actor.first_name, actor.last_name, actor.email),
      "email_initial" => Locations.initial(actor.email),
      "latitude" => p["latitude"] * 1.0,
      "longitude" => p["longitude"] * 1.0,
      "timestamp" => p["timestamp"],
      "updated_at" => iso
    }
  end

  defp publish_shares(repo, user, point, now) do
    links =
      repo.query!(
        "SELECT id::text FROM shared_links WHERE user_id=$1 AND resource_type=3 AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at>$2)",
        [user, DateTime.to_naive(now)],
        log: false
      ).rows

    if links != [] do
      Dawarich.Sharing.Events.enqueue(repo, user, List.flatten(links))
      geom = "ST_SetSRID(ST_MakePoint($2,$3),4326)::geography"

      [[public]] =
        repo.query!(
          "SELECT " <> Dawarich.SharedApi.Privacy.outside(geom),
          [user, point["longitude"] * 1.0, point["latitude"] * 1.0],
          log: false
        ).rows

      message =
        if public,
          do: %{
            "lat" => point["latitude"] * 1.0,
            "lon" => point["longitude"] * 1.0,
            "ts" => point["timestamp"]
          },
          else: %{"masked" => true}

      for [id] <- links,
          do: :ok = Cable.broadcast_to("shared_location", {:shared_link, id}, message, repo: repo)
    end
  end

  defp text(nil), do: ""
  defp text(value), do: to_string(value)
end
