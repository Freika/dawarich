defmodule DawarichWeb.StandaloneAreaCleanupTest do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  alias Dawarich.Test.RailsUser

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    previous = Map.new(~w(DAWARICH_RAILS SELF_HOSTED FORCE_SSL), &{&1, System.get_env(&1)})
    System.put_env(%{"DAWARICH_RAILS" => "off", "SELF_HOSTED" => "true", "FORCE_SSL" => "false"})

    on_exit(fn ->
      for {k, v} <- previous, do: if(v, do: System.put_env(k, v), else: System.delete_env(k))
    end)

    users =
      for _ <- 1..2,
          do:
            RailsUser.insert!(%{
              id: System.unique_integer([:positive]),
              email: "rereview-#{Ecto.UUID.generate()}@example.invalid",
              api_key: Ecto.UUID.generate(),
              settings: %{"timezone" => "UTC"}
            })

    %{actor: hd(users), other: List.last(users)}
  end

  for kind <- [:declined, :soft_deleted, :foreign_suggestion] do
    @tag :queued_foreign
    @tag :"queued_#{kind}"
    test "queued area cleanup preserves foreign shared place attachments #{kind}", c do
      assert_queued_cleanup(c, unquote(kind))
    end
  end

  defp assert_queued_cleanup(c, kind) do
    area = area(c.actor)
    other_area = area(c.other)
    place = place(c.actor)
    visit(c.actor, area, place)
    foreign_place = if kind == :foreign_suggestion, do: place(c.other), else: place
    foreign = visit(c.other, other_area, foreign_place)
    if kind == :declined, do: rows("UPDATE visits SET status=2 WHERE id=$1", [foreign])

    if kind == :soft_deleted,
      do: rows("UPDATE visits SET deleted_at=now() WHERE id=$1", [foreign])

    [[link]] =
      rows(
        "INSERT INTO place_visits(place_id,visit_id,created_at,updated_at) VALUES($1,$2,now(),now()) RETURNING id",
        [place, foreign]
      )

    before = foreign_snapshot(c.other)
    assert request(c.actor, "/api/v1/areas/#{area}").status == 200

    [[args]] =
      rows(
        "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Places.DeleteIfOrphanWorker' AND args->>'place_id'=$1",
        [to_string(place)]
      )

    assert Dawarich.Places.DeleteIfOrphanWorker.run(Repo, args) == :ok

    primary_survives =
      rows("SELECT place_id FROM visits WHERE id=$1", [foreign]) == [[foreign_place]]

    link_survives = rows("SELECT id FROM place_visits WHERE id=$1", [link]) == [[link]]
    assert foreign_snapshot(c.other) == before
    assert primary_survives
    assert link_survives
    assert rows("SELECT id FROM places WHERE id=$1", [place]) == [[place]]
  end

  defp foreign_snapshot(user) do
    Map.new(~w(areas visits places), fn table ->
      {table,
       rows("SELECT row_to_json(t)::text FROM #{table} t WHERE user_id=$1 ORDER BY id", [user.id])}
    end)
    |> Map.put(
      :links,
      rows(
        "SELECT row_to_json(pv)::text FROM place_visits pv JOIN visits v ON v.id=pv.visit_id WHERE v.user_id=$1 ORDER BY pv.id",
        [user.id]
      )
    )
  end

  defp area(user),
    do:
      rows(
        "INSERT INTO areas(user_id,name,latitude,longitude,radius,created_at,updated_at) VALUES($1,'Synthetic',52.5,13.4,100,now(),now()) RETURNING id",
        [user.id]
      )
      |> hd()
      |> hd()

  defp place(user),
    do:
      rows(
        "INSERT INTO places(user_id,name,latitude,longitude,source,created_at,updated_at) VALUES($1,'Synthetic',52.5,13.4,1,now(),now()) RETURNING id",
        [user.id]
      )
      |> hd()
      |> hd()

  defp visit(user, area, place),
    do:
      rows(
        "INSERT INTO visits(user_id,area_id,place_id,name,started_at,ended_at,duration,status,demo,created_at,updated_at) VALUES($1,$2,$3,'Synthetic','2024-01-01','2024-01-01 01:00:00',3600,1,false,now(),now()) RETURNING id",
        [user.id, area, place]
      )
      |> hd()
      |> hd()

  defp request(actor, path) do
    Plug.Test.conn(:delete, path, "{}")
    |> put_req_header("content-length", "2")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer " <> actor.api_key)
    |> DawarichWeb.Endpoint.call(DawarichWeb.Endpoint.init([]))
  end
end
