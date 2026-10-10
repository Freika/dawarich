defmodule Dawarich.Areas.CommandsTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.{Accounts, Areas, Maps}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.RailsUser

  @now ~U[2026-10-10 10:00:00.000000Z]

  setup do
    for key <- ~w(areas.relabel_visits places.delete_if_orphan),
        do: Ownership.put!(Repo, "command:" <> key, :oban)

    [actor, other] = for _ <- 1..2, do: account!()
    %{scope: Maps.principal(actor, "en"), actor: actor, other: other}
  end

  test "Area rounding-equivalent update is a no-op after relabel consumption", c do
    attrs = %{"name" => "Home", "latitude" => "51.5", "longitude" => "12.25", "radius" => "200"}
    assert {:ok, %{"id" => id, "radius" => 200}} = Areas.create_area(c.scope, attrs, now: @now)
    assert outbox(id) == 1
    rows("DELETE FROM public.job_outbox WHERE aggregate_id=$1", [id])
    [[stamp]] = rows("SELECT updated_at FROM areas WHERE id=$1", [id])

    equivalent = %{
      attrs
      | "latitude" => "51.5000004",
        "longitude" => "+12.2500001",
        "radius" => "200.9"
    }

    assert {:ok, %{"id" => ^id}} =
             Areas.update_area(c.scope, id, equivalent, now: DateTime.add(@now, 60))

    assert rows("SELECT updated_at, latitude::text FROM areas WHERE id=$1", [id]) ==
             [[stamp, "51.500000"]]

    assert outbox(id) == 0

    assert {:ok, %{"name" => "Office"}} =
             Areas.update_area(c.scope, id, %{"name" => "Office"}, now: DateTime.add(@now, 120))

    assert outbox(id) == 0
  end

  test "Area delete preserves foreign shared dependencies", c do
    area = area!(c.actor)
    visit!(c.actor, area, place!(c.other))
    snapshot = graph(c.actor)

    assert {:error, :foreign_area_dependency} = Areas.delete_area(c.scope, area)
    assert graph(c.actor) == snapshot

    own = area!(c.actor)
    visit = visit!(c.actor, own, place!(c.actor))
    assert :ok = Areas.delete_area(c.scope, own)
    assert rows("SELECT count(*) FROM areas WHERE id=$1", [own]) == [[0]]
    assert rows("SELECT count(*) FROM visits WHERE id=$1", [visit]) == [[0]]

    assert rows(
             "SELECT count(*) FROM public.job_outbox WHERE command_type='places.delete_if_orphan'"
           ) == [[1]]
  end

  test "revoked scope cannot update or delete", c do
    area = area!(c.actor)
    snapshot = graph(c.actor)

    rows("UPDATE users SET encrypted_password=$1 WHERE id=$2", [
      String.duplicate("rotated", 10),
      c.actor.id
    ])

    assert {:error, :stale_session} =
             Areas.update_area(c.scope, area, %{"radius" => "900"}, now: @now)

    assert {:error, :stale_session} = Areas.delete_area(c.scope, area)
    assert {:error, :stale_session} = Areas.create_area(c.scope, %{"name" => "x"}, now: @now)
    assert graph(c.actor) == snapshot
    assert outbox(area) == 0
  end

  test "Area commands refuse foreign ids and return typed validation errors", c do
    foreign = area!(c.other)
    assert {:error, :not_found} = Areas.get_area(c.scope, foreign)

    assert {:error, :not_found} =
             Areas.update_area(c.scope, foreign, %{"radius" => "5"}, now: @now)

    assert {:error, :not_found} = Areas.delete_area(c.scope, foreign)
    assert {:error, :not_found} = Areas.delete_area(c.scope, "99999999999999999999999")

    assert {:error, {:invalid, errors}} =
             Areas.create_area(
               c.scope,
               %{"name" => "A", "latitude" => "1", "longitude" => "1", "radius" => "-1"},
               now: @now
             )

    assert errors == ["Radius must be greater than 0"]
    assert rows("SELECT count(*) FROM areas WHERE user_id=$1", [c.actor.id]) == [[0]]
    assert rows("SELECT radius FROM areas WHERE id=$1", [foreign]) == [[100]]
  end

  defp account! do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "areas-#{id}@dawarich.test",
      api_key: Ecto.UUID.generate(),
      settings: %{"timezone" => "UTC"}
    })

    Accounts.get(id)
  end

  defp outbox(id),
    do:
      rows(
        "SELECT count(*) FROM public.job_outbox WHERE command_type='areas.relabel_visits' AND aggregate_id=$1",
        [id]
      )
      |> hd()
      |> hd()

  defp graph(user) do
    for table <- ~w(areas visits places notes),
        do:
          rows("SELECT row_to_json(t)::text FROM #{table} t WHERE user_id=$1 ORDER BY id", [
            user.id
          ])
  end

  defp area!(user),
    do:
      one(
        "INSERT INTO areas(user_id,name,latitude,longitude,radius,created_at,updated_at) VALUES($1,'Synthetic',52.5,13.4,100,now(),now()) RETURNING id",
        [user.id]
      )

  defp place!(user),
    do:
      one(
        "INSERT INTO places(user_id,name,latitude,longitude,source,created_at,updated_at) VALUES($1,'Synthetic',52.5,13.4,1,now(),now()) RETURNING id",
        [user.id]
      )

  defp visit!(user, area, place),
    do:
      one(
        "INSERT INTO visits(user_id,area_id,place_id,name,started_at,ended_at,duration,status,demo,created_at,updated_at) VALUES($1,$2,$3,'Synthetic','2024-01-01','2024-01-01 01:00:00',3600,1,false,now(),now()) RETURNING id",
        [user.id, area, place]
      )

  defp one(sql, params), do: rows(sql, params) |> hd() |> hd()
end
