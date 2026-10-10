defmodule Dawarich.LocationCommands.PointsTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.{Accounts, Maps}
  alias Dawarich.LocationCommands.Points
  alias Dawarich.Test.RailsUser

  @scope %{"start_at" => "2026-09-28T00:00Z", "end_at" => "2026-09-29T00:00Z"}
  @opts [self_hosted?: true, now: ~U[2026-10-10 10:00:00Z]]

  setup do
    [actor, other] = for _ <- 1..2, do: account!()
    %{scope: Maps.principal(actor, "en"), actor: actor, other: other}
  end

  test "foreign or stale point command has no side effects", c do
    own = point!(c.actor, 1_790_593_200)
    foreign = point!(c.other, 1_790_593_200)
    before = snapshot([own, foreign])

    assert {:error, :not_found} = Points.move(c.scope, foreign, move(0), @opts)
    assert {:error, :not_found} = Points.delete(c.scope, foreign, @opts)
    assert {:ok, 0} = Points.bulk_delete(c.scope, [to_string(foreign)], @opts)

    assert {:error, {:stale, %{"revision" => %{"point" => 0}}}} =
             Points.move(c.scope, own, move(7), @opts)

    assert snapshot([own, foreign]) == before

    assert rows("SELECT count(*) FROM phoenix.rails_commands WHERE payload->>'user_id'=$1", [
             to_string(c.other.id)
           ]) == [[0]]

    assert {:ok, %{"revision" => %{"point" => 1}}} = Points.move(c.scope, own, move(0), @opts)

    assert rows("SELECT ST_Y(lonlat::geometry), lock_version FROM points WHERE id=$1", [own]) == [
             [51.0, 1]
           ]

    rows("UPDATE users SET encrypted_password=$1 WHERE id=$2", [
      String.duplicate("rotated", 10),
      c.actor.id
    ])

    moved = snapshot([own])
    assert {:error, :stale_session} = Points.move(c.scope, own, move(1), @opts)
    assert {:error, :stale_session} = Points.bulk_delete(c.scope, [own], @opts)
    assert snapshot([own]) == moved
  end

  test "bulk delete publishes original counter and tile effects once", c do
    [[import]] =
      rows(
        "INSERT INTO imports(user_id,name,status,points_count,created_at,updated_at) VALUES($1,'synthetic.json',2,10,now(),now()) RETURNING id",
        [c.actor.id]
      )

    rows("UPDATE users SET points_count=10 WHERE id IN ($1,$2)", [c.actor.id, c.other.id])
    first = point!(c.actor, 1_790_593_200, import)
    second = point!(c.actor, 1_790_593_260, import)
    kept = point!(c.actor, 1_790_593_320, import)
    foreign = point!(c.other, 1_790_593_200)

    ids = [first, to_string(second), first, " #{second}", foreign]
    assert {:ok, 2} = Points.bulk_delete(c.scope, ids, @opts)

    assert rows("SELECT id FROM points WHERE id = ANY($1) ORDER BY id", [
             [first, second, kept, foreign]
           ]) ==
             [[kept], [foreign]]

    assert rows("SELECT points_count FROM users WHERE id=$1", [c.actor.id]) == [[8]]
    assert rows("SELECT points_count FROM users WHERE id=$1", [c.other.id]) == [[10]]

    assert rows("SELECT points_count FROM imports WHERE id=$1", [import]) == [[8]]

    assert [[payload]] =
             rows(
               "SELECT payload FROM phoenix.rails_commands WHERE kind='points.web_destroy_follow_up' AND payload->>'user_id'=$1",
               [to_string(c.actor.id)]
             )

    assert payload["timestamps"] == [1_790_593_200, 1_790_593_260]

    assert {:error, {:invalid, "no_points_selected"}} = Points.bulk_delete(c.scope, [], @opts)

    assert {:error, {:invalid, "too_many_points_selected"}} =
             Points.bulk_delete(c.scope, Enum.to_list(1..5001), @opts)
  end

  defp move(revision),
    do: %{
      "point" => %{"latitude" => "51", "longitude" => "14", "revision" => revision},
      "history_scope" => @scope
    }

  defp snapshot(ids),
    do: rows("SELECT row_to_json(p)::text FROM points p WHERE id = ANY($1) ORDER BY id", [ids])

  defp point!(user, timestamp, import \\ nil),
    do:
      rows(
        "INSERT INTO points(user_id,timestamp,import_id,lonlat,created_at,updated_at) VALUES($1,$2,$3,'POINT(13.4 52.5)',now(),now()) RETURNING id",
        [user.id, timestamp, import]
      )
      |> hd()
      |> hd()

  defp account! do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "points-#{id}@dawarich.test",
      api_key: Ecto.UUID.generate(),
      settings: %{"timezone" => "UTC"}
    })

    Accounts.get(id)
  end
end
