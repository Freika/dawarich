defmodule DawarichWeb.StandaloneApiReviewTest do
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

    [actor, other] =
      for _ <- 1..2 do
        RailsUser.insert!(%{
          id: System.unique_integer([:positive]),
          email: "review-#{Ecto.UUID.generate()}@example.invalid",
          api_key: Ecto.UUID.generate(),
          settings: %{"timezone" => "UTC"}
        })
      end

    %{actor: actor, other: other}
  end

  @tag :review_area_foreign
  test "owned area deletion refuses every foreign dependent before changing the graph", c do
    for {kind, index} <-
          Enum.with_index([
            :foreign_visit,
            :foreign_point,
            :foreign_area_note,
            :foreign_visit_note,
            :foreign_place_visit
          ]) do
      [[area]] =
        rows(
          "INSERT INTO areas(user_id,name,latitude,longitude,radius,created_at,updated_at) VALUES($1,'Synthetic',52.5,13.4,100,now(),now()) RETURNING id",
          [c.actor.id]
        )

      [[visit]] =
        rows(
          "INSERT INTO visits(user_id,area_id,name,started_at,ended_at,duration,status,demo,created_at,updated_at) VALUES($1,$2,'Synthetic','2024-01-01','2024-01-01 01:00:00',3600,1,false,now(),now()) RETURNING id",
          [if(kind == :foreign_visit, do: c.other.id, else: c.actor.id), area]
        )

      [[note]] =
        rows(
          "INSERT INTO notes(user_id,attachable_type,attachable_id,body,created_at,updated_at) VALUES($1,$2,$3,'Synthetic',now(),now()) RETURNING id",
          [
            if(kind in [:foreign_visit, :foreign_area_note, :foreign_visit_note],
              do: c.other.id,
              else: c.actor.id
            ),
            if(kind == :foreign_visit_note, do: "Visit", else: "Area"),
            if(kind == :foreign_visit_note, do: visit, else: area)
          ]
        )

      point =
        Dawarich.Test.DemoData.real_point(
          if(kind in [:foreign_visit, :foreign_point], do: c.other.id, else: c.actor.id),
          1_704_067_200 + index
        )

      rows("UPDATE points SET visit_id=$2 WHERE id=$1", [point, visit])

      [[place]] =
        rows(
          "INSERT INTO places(user_id,name,latitude,longitude,source,created_at,updated_at) VALUES($1,'Synthetic',52.5,13.4,1,now(),now()) RETURNING id",
          [if(kind in [:foreign_visit, :foreign_place_visit], do: c.other.id, else: c.actor.id)]
        )

      [[link]] =
        rows(
          "INSERT INTO place_visits(place_id,visit_id,created_at,updated_at) VALUES($1,$2,now(),now()) RETURNING id",
          [place, visit]
        )

      before = rows("SELECT worker,args FROM oban.oban_jobs ORDER BY id")
      conn = request(c.actor, :delete, "/api/v1/areas/#{area}")
      assert rows("SELECT id FROM visits WHERE id=$1", [visit]) == [[visit]]
      assert rows("SELECT id FROM notes WHERE id=$1", [note]) == [[note]]
      assert rows("SELECT visit_id FROM points WHERE id=$1", [point]) == [[visit]]
      assert rows("SELECT id FROM areas WHERE id=$1", [area]) == [[area]]
      assert rows("SELECT id FROM place_visits WHERE id=$1", [link]) == [[link]]
      assert rows("SELECT worker,args FROM oban.oban_jobs ORDER BY id") == before
      assert conn.status == 422
      assert Jason.decode!(conn.resp_body) == %{"error" => "Area has foreign dependents"}
    end
  end

  @tag :review_area_id
  test "out of range area ids return the Rails JSON record not found response", c do
    for id <- ["999999999999999999999999999999", "9223372036854775808", "-9223372036854775809"] do
      conn = request(c.actor, :delete, "/api/v1/areas/#{id}")
      assert conn.status == 404
      assert Jason.decode!(conn.resp_body) == %{"error" => "Record not found"}
    end
  end

  @tag :review_digest_year
  test "malformed member years cannot delete a real digest", c do
    [[digest]] =
      rows(
        "INSERT INTO digests(user_id,year,period_type,created_at,updated_at) VALUES($1,2024,1,now(),now()) RETURNING id",
        [c.actor.id]
      )

    for year <- [
          "2024tail",
          "2024tail.json",
          "999999999999999999999999999999",
          "202",
          "20240",
          "+2024",
          "-2024"
        ] do
      conn = request(c.actor, :delete, "/api/v1/digests/#{year}")
      assert rows("SELECT id FROM digests WHERE id=$1", [digest]) == [[digest]]
      assert conn.status == 404
    end

    assert request(c.actor, :delete, "/api/v1/digests/2024.json").status == 204
    assert rows("SELECT id FROM digests WHERE id=$1", [digest]) == []
  end

  defp request(actor, method, path) do
    Plug.Test.conn(method, path, "{}")
    |> put_req_header("content-length", "2")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer " <> actor.api_key)
    |> DawarichWeb.Endpoint.call(DawarichWeb.Endpoint.init([]))
  end
end
