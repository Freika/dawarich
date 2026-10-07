defmodule DawarichWeb.SettingsApiParityTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Dawarich.IngestCase, only: [user!: 1]
  alias Dawarich.Repo

  setup tags do
    if tags[:unboxed] do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual) end)
    else
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    end

    env = Map.take(System.get_env(), ~w(DAWARICH_RAILS SELF_HOSTED TIME_ZONE))
    System.put_env(%{"DAWARICH_RAILS" => "off", "SELF_HOSTED" => "true", "TIME_ZONE" => "UTC"})
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    key = "settings-parity-#{System.unique_integer([:positive])}"
    id = user!(%{api_key: key, settings: %{}, plan: 1})

    previous_owner =
      Repo.query!(
        "SELECT owner,pinned,updated_at,updated_by FROM phoenix.job_owners WHERE key='command:areas.relabel_visits'"
      ).rows

    Dawarich.Jobs.Ownership.put!(Repo, "command:areas.relabel_visits", :oban)

    on_exit(fn ->
      for name <- ~w(DAWARICH_RAILS SELF_HOSTED TIME_ZONE) do
        if env[name], do: System.put_env(name, env[name]), else: System.delete_env(name)
      end

      if tags[:unboxed] do
        Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
          Repo.query!(
            "DELETE FROM job_outbox WHERE command_type='areas.relabel_visits' AND aggregate_id IN (SELECT id FROM areas WHERE user_id=$1)",
            [id]
          )

          Repo.query!("DELETE FROM areas WHERE user_id=$1", [id])
          Repo.query!("DELETE FROM users WHERE id=$1", [id])

          case previous_owner do
            [] ->
              Repo.query!(
                "DELETE FROM phoenix.job_owners WHERE key='command:areas.relabel_visits'"
              )

            [values] ->
              Repo.query!(
                "UPDATE phoenix.job_owners SET owner=$1,pinned=$2,updated_at=$3,updated_by=$4 WHERE key='command:areas.relabel_visits'",
                values
              )
          end
        end)
      end
    end)

    %{id: id, key: key}
  end

  test "Rails accepted timezones render mobile and area endpoints using application data", c do
    cases =
      Path.expand("../fixtures/settings_api_time_zones.json", __DIR__)
      |> File.read!()
      |> Jason.decode!()

    for {row, index} <- Enum.with_index(cases) do
      assert request(c, :patch, "/api/v1/settings", %{"settings" => %{"timezone" => row["zone"]}}).status ==
               200

      assert settings(c.id)["timezone"] == row["zone"]

      {:ok, now, _} = DateTime.from_iso8601(row["at"])
      ctx = %{now: now}

      mobile =
        request(
          c,
          :patch,
          "/api/v1/settings/mobile",
          %{"settings" => %{"auto_start" => true}},
          ctx
        )

      assert mobile.status == 200, "mobile #{row["zone"]}: #{mobile.resp_body}"
      assert body(mobile)["updated_at"] == row["mobile"]
      area = request(c, :post, "/api/v1/areas", area_params(), ctx)
      assert area.status == 201, "area #{row["zone"]}: #{area.resp_body}"
      area = body(area)
      assert area["created_at"] == row["area"]
      assert area["updated_at"] == row["area"]

      if index < 96 do
        assert body(request(c, :get, "/api/v1/settings/mobile"))["updated_at"] == row["mobile"]
        assert body(request(c, :get, "/api/v1/areas/#{area["id"]}")) == area
        assert area in body(request(c, :get, "/api/v1/areas"))

        updated =
          request(
            c,
            :patch,
            "/api/v1/areas/#{area["id"]}",
            %{"area" => %{"name" => "Renamed"}},
            ctx
          )

        assert updated.status == 200
        assert body(updated)["updated_at"] == row["area"]
      end

      Repo.query!(
        "DELETE FROM job_outbox WHERE command_type='areas.relabel_visits' AND aggregate_id=$1",
        [area["id"]]
      )

      Repo.query!("DELETE FROM areas WHERE id=$1", [area["id"]])
    end
  end

  @tag :unboxed
  test "response rendering failures roll back mobile and area writes and outbox effects", c do
    verifier =
      start_supervised!(
        {Postgrex,
         Keyword.take(Repo.config(), [:hostname, :port, :username, :password, :database])}
      )

    invalid = area_params() |> put_in(["area", "radius"], 0)
    assert request(c, :post, "/api/v1/areas", invalid).status == 422
    ctx = %{render_response: fn _ -> raise "synthetic rendering failure" end}

    assert request(
             c,
             :patch,
             "/api/v1/settings/mobile",
             %{"settings" => %{"auto_start" => true}},
             ctx
           ).status == 500

    assert Postgrex.query!(verifier, "SELECT settings FROM users WHERE id=$1", [c.id]).rows == [
             [%{}]
           ]

    assert request(c, :post, "/api/v1/areas", area_params(), ctx).status == 500

    assert Postgrex.query!(verifier, "SELECT count(*) FROM areas WHERE user_id=$1", [c.id]).rows ==
             [[0]]

    area = request(c, :post, "/api/v1/areas", area_params()) |> body()

    Repo.query!(
      "DELETE FROM job_outbox WHERE command_type='areas.relabel_visits' AND aggregate_id=$1",
      [area["id"]]
    )

    assert request(
             c,
             :patch,
             "/api/v1/areas/#{area["id"]}",
             %{"area" => %{"name" => "Failed", "radius" => 200}},
             ctx
           ).status == 500

    assert Postgrex.query!(verifier, "SELECT name,radius FROM areas WHERE id=$1", [area["id"]]).rows ==
             [["Zone", 100]]

    assert Postgrex.query!(
             verifier,
             "SELECT count(*) FROM job_outbox WHERE command_type='areas.relabel_visits' AND aggregate_id=$1",
             [area["id"]]
           ).rows == [[0]]
  end

  test "malformed style URLs return Rails validation errors without persisting", c do
    original = settings(c.id)

    for url <- [
          "https://styles.example.invalid/style path",
          "https://bad host/style.json",
          "/style\n.json",
          "https://styles.example.invalid/雪.json",
          "https://styles.example.invalid/%zz.json",
          "https://styles.example.invalid:bad/style.json"
        ] do
      response =
        request(c, :patch, "/api/v1/settings", %{
          "settings" => %{"maps_maplibre_tiles_url" => url}
        })

      assert response.status == 422, url

      assert body(response) == %{
               "message" => "Something went wrong",
               "errors" => [
                 "Tile URL must include {z}, {x}, and {y} placeholders, or be a MapLibre style URL"
               ]
             }

      assert settings(c.id) == original
    end

    for url <- [
          "https://styles.example.invalid/style.json?key=a%20b",
          "/style.json",
          "https://tiles.example.invalid/{z}/{x}/{y}.pbf",
          "https://bad host/{z}/{x}/{y}"
        ] do
      assert request(c, :patch, "/api/v1/settings", %{
               "settings" => %{"maps_maplibre_tiles_url" => url}
             }).status == 200
    end

    corpus =
      Path.expand("../fixtures/settings_api_style_urls.json", __DIR__)
      |> File.read!()
      |> Jason.decode!()

    for row <- corpus do
      before = settings(c.id)

      response =
        request(c, :patch, "/api/v1/settings", %{
          "settings" => %{"maps_maplibre_tiles_url" => row["url"]}
        })

      assert response.status == row["status"], inspect(row["url"])
      if row["status"] == 422, do: assert(settings(c.id) == before)
    end
  end

  test "null stored settings return the ordinary Rails defaults", c do
    expected = request(c, :get, "/api/v1/settings") |> body()
    Repo.query!("UPDATE users SET settings='null'::jsonb WHERE id=$1", [c.id])
    response = request(c, :get, "/api/v1/settings")
    assert response.status == 200
    assert body(response) == expected
    Repo.query!("UPDATE users SET settings=NULL WHERE id=$1", [c.id])
    assert body(request(c, :get, "/api/v1/settings")) == expected
  end

  test "null timezone returns the configured Rails default", c do
    Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [c.id, %{"timezone" => nil}])

    for zone <- ["UTC", "Europe/Berlin"] do
      System.put_env("TIME_ZONE", zone)
      response = request(c, :get, "/api/v1/settings")
      assert response.status == 200
      assert body(response)["settings"]["timezone"] == zone
    end
  end

  defp area_params,
    do: %{"area" => %{"name" => "Zone", "latitude" => 52, "longitude" => 13, "radius" => 100}}

  defp settings(id),
    do: Repo.query!("SELECT settings FROM users WHERE id=$1", [id]).rows |> hd() |> hd()

  defp body(conn), do: Jason.decode!(conn.resp_body)

  defp request(c, method, path, params \\ %{}, ctx \\ %{}) do
    Plug.Test.conn(method, path, Jason.encode!(params))
    |> put_req_header("content-length", to_string(byte_size(Jason.encode!(params))))
    |> put_req_header("authorization", "Bearer " <> c.key)
    |> put_req_header("content-type", "application/json")
    |> assign(:api_context, ctx)
    |> DawarichWeb.Endpoint.call([])
  end
end
