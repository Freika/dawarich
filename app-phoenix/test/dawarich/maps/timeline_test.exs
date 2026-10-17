defmodule Dawarich.Maps.TimelineTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.{Accounts, Maps}
  alias Dawarich.Maps.Timeline
  alias Dawarich.Test.RailsUser

  @opts [now: ~U[2026-04-02 10:00:00Z], self_hosted?: true]

  setup do
    [actor, other] = for _ <- 1..2, do: account!()
    %{scope: Maps.principal(actor, "en"), actor: actor, other: other}
  end

  test "map timeline uses M5 cursor pages without losing owned legs", c do
    owned =
      for minute <- 0..104 do
        from = NaiveDateTime.add(~N[2026-03-29 08:00:00], minute * 60)
        track!(c.actor, from, NaiveDateTime.add(from, 30))
      end

    params = %{"start_at" => "2026-03-29T00:00", "end_at" => "2026-03-29T23:59"}
    assert {:ok, first} = Timeline.feed(c.scope, params, @opts)
    assert length(legs(first)) == 100
    assert is_binary(first.next_cursor)

    assert {:ok, last} =
             Timeline.feed(c.scope, Map.put(params, "cursor", first.next_cursor), @opts)

    assert length(legs(last)) == 5
    assert last.next_cursor == nil
    assert MapSet.new(legs(first) ++ legs(last)) == MapSet.new(owned)
  end

  test "local day midnight and DST return the same owned legs", c do
    early = track!(c.actor, ~N[2026-03-28 23:10:00], ~N[2026-03-28 23:40:00])
    late = track!(c.actor, ~N[2026-03-29 21:30:00], ~N[2026-03-29 21:50:00])
    track!(c.actor, ~N[2026-03-29 22:30:00], ~N[2026-03-29 22:50:00])
    track!(c.other, ~N[2026-03-29 08:00:00], ~N[2026-03-29 09:00:00])

    day = %{"start_at" => "2026-03-29T00:00", "end_at" => "2026-03-29T23:59"}
    assert {:ok, feed} = Timeline.feed(c.scope, day, @opts)
    assert feed.requested_date == ~D[2026-03-29]
    assert Enum.map(feed.days, & &1.date) == ["2026-03-29"]
    assert legs(feed) == [early, late]
    assert {:ok, %{id: ^early}} = Timeline.track(c.scope, early)
    [[foreign]] = rows("SELECT id FROM tracks WHERE user_id=$1", [c.other.id])
    assert {:error, :not_found} = Timeline.track(c.scope, foreign)
  end

  test "invalid day uses established fallback", c do
    today = track!(c.actor, ~N[2026-04-02 09:50:00], ~N[2026-04-02 10:20:00])
    track!(c.actor, ~N[2026-04-02 07:00:00], ~N[2026-04-02 07:30:00])

    for params <- [
          %{},
          %{"start_at" => "", "end_at" => ""},
          %{"start_at" => "garbage", "end_at" => "garbage"}
        ] do
      assert {:ok, feed} = Timeline.feed(c.scope, params, @opts)
      assert feed.requested_date == ~D[2026-04-02]
      assert legs(feed) == [today]
    end

    assert {:error, :invalid} = Timeline.feed(c.scope, %{"start_at" => ["x"]}, @opts)
  end

  test "search considers end time", c do
    overnight = track!(c.actor, ~N[2026-03-29 20:00:00], ~N[2026-03-30 06:30:00])

    assert {:ok, feed} =
             Timeline.feed(
               c.scope,
               %{"start_at" => "2026-03-30T00:00", "end_at" => "2026-03-30T23:59"},
               @opts
             )

    assert overnight in legs(feed)

    rows("UPDATE users SET encrypted_password=$1 WHERE id=$2", [
      String.duplicate("rotated", 10),
      c.actor.id
    ])

    assert {:error, :stale_session} = Timeline.feed(c.scope, %{}, @opts)
  end

  defp legs(feed),
    do:
      for(
        day <- feed.days,
        entry <- day.entries,
        entry.type == "journey",
        uniq: true,
        do: entry.track_id
      )

  defp track!(user, from, to) do
    rows(
      "INSERT INTO tracks(user_id,start_at,end_at,distance,duration,dominant_mode,original_path,created_at,updated_at) VALUES($1,$2,$3,5000,$4,3,ST_GeomFromText('LINESTRING(13.4 52.5,13.5 52.6)',4326),now(),now()) RETURNING id",
      [user.id, from, to, NaiveDateTime.diff(to, from)]
    )
    |> hd()
    |> hd()
  end

  defp account! do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "timeline-#{id}@dawarich.test",
      settings: %{"timezone" => "Europe/Berlin"}
    })

    Accounts.get(id)
  end
end
