defmodule DawarichWeb.AchievementPublicTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Phoenix.ConnTest
  alias Dawarich.Achievements.Registry
  alias Dawarich.Repo
  alias Dawarich.Test.{ParityHTML, RailsUser}
  alias DawarichWeb.AchievementPublicPage

  @root "test/fixtures/achievement_public"
  @scripts "script[type='importmap'],script#i18n-translations,link[rel='modulepreload']"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Dawarich.Test.AchievementSilhouettes.clear()
    on_exit(&Dawarich.Test.AchievementSilhouettes.clear/0)
    square = "MULTIPOLYGON (((12.25 51.25,12.25 51.5,12.5 51.5,12.5 51.25,12.25 51.25)))"

    for code <- ~w(DE FR),
        do:
          rows(
            "INSERT INTO countries(iso_a2,iso_a3,name,geom,created_at,updated_at) VALUES($1,$1,$1,ST_GeomFromText($2,4326),now(),now())",
            [code, square]
          )

    :ok
  end

  test "serves Rails public and embed documents with owner metadata and no private chrome" do
    :persistent_term.put({DawarichWeb.Assets, :rails_imports}, %{
      "application" => "/assets/application-public-test.js"
    })

    on_exit(fn -> :persistent_term.erase({DawarichWeb.Assets, :rails_imports}) end)

    corpus =
      File.read!("#{@root}/public.json")
      |> Jason.decode!()
      |> Enum.filter(&(&1["status"] == 200 and &1["method"] == "GET"))

    for row <- corpus do
      seed(row)
      before = snapshot()
      result = request(row["method"], row["path"], row["params"])
      assert result.status == 200, row["name"]
      html = result.resp_body
      expected = File.read!("#{@root}/#{row["html_file"]}")

      assert ParityHTML.fragment(html, "body") == ParityHTML.fragment(expected, "body"),
             ParityHTML.first_difference(
               ParityHTML.fragment(html, "body"),
               ParityHTML.fragment(expected, "body")
             )

      assert ParityHTML.without(html, [@scripts], "head") ==
               ParityHTML.without(expected, [@scripts], "head"),
             ParityHTML.first_difference(
               ParityHTML.without(html, [@scripts], "head"),
               ParityHTML.without(expected, [@scripts], "head")
             )

      doc = LazyHTML.from_document(html)
      assert LazyHTML.query(doc, "html") |> LazyHTML.attribute("lang") == [row["lang"]]
      assert LazyHTML.query(doc, "header") |> Enum.count() == if(row["chrome"], do: 1, else: 0)
      assert LazyHTML.query(doc, "footer") |> Enum.count() == if(row["chrome"], do: 1, else: 0)
      assert LazyHTML.query(doc, ".ach-card") |> Enum.count() == 1

      assert LazyHTML.query(doc, ".ach-child-grid, [data-controller='achievement-unlocks']")
             |> Enum.count() == 0

      assert LazyHTML.query(doc, "script[type='importmap']")
             |> LazyHTML.text()
             |> Jason.decode!()
             |> Map.fetch!("imports")
             |> Map.fetch!("application") == DawarichWeb.Assets.rails_imports()["application"]

      for {key, value} <- row["metadata"],
          do:
            assert(
              LazyHTML.query(doc, "meta[property='#{key}'],meta[name='#{key}']")
              |> LazyHTML.attribute("content") == [value]
            )

      refute html =~ "example.invalid"
      refute html =~ "data-phx"
      assert snapshot() == before
    end
  end

  test "preserves embedding and not-found redirect header flash and HEAD semantics" do
    rows = File.read!("#{@root}/public.json") |> Jason.decode!()
    visible = Enum.find(rows, &(&1["name"] == "en_direct"))
    seed(visible)
    head = request("HEAD", visible["path"], %{})
    assert head.status == 200 and head.resp_body == ""
    assert get_resp_header(head, "cache-control") == ["max-age=0, private, must-revalidate"]
    assert get_resp_header(head, "x-frame-options") == []
    assert get_resp_header(head, "content-security-policy") == ["frame-ancestors *"]

    for name <- ~w(disabled missing_definition deleted_owner unknown_uuid unknown_head) do
      row = Enum.find(rows, &(&1["name"] == name))

      seed(%{
        visible
        | "owner_id" => 43031,
          "path" => "/shared/achievements/a10c0000-0000-4000-8000-000000043031"
      })

      rows("UPDATE users SET deleted_at=NULL WHERE id=43031")

      rows(
        "UPDATE achievement_progresses SET sharing_enabled=true,achievement_key='country_de' WHERE sharing_uuid='a10c0000-0000-4000-8000-000000043031'"
      )

      case name do
        "disabled" ->
          rows("UPDATE achievement_progresses SET sharing_enabled=false WHERE user_id=43031")

        "missing_definition" ->
          rows(
            "UPDATE achievement_progresses SET achievement_key='missing_definition' WHERE user_id=43031 AND sharing_uuid IS NOT NULL"
          )

        "deleted_owner" ->
          rows("UPDATE users SET deleted_at=now() WHERE id=43031")

        _ ->
          :ok
      end

      result = request(row["method"], row["path"], row["params"])
      assert result.status == row["status"] and result.resp_body == ""
      assert get_resp_header(result, "location") == [row["location"]]
      assert get_resp_header(result, "x-frame-options") == []
      assert get_resp_header(result, "content-security-policy") == ["frame-ancestors *"]
      assert get_resp_header(result, "cache-control") == ["no-cache"]
      assert result.private.dawarich_rails_session_changes["flash"]["flashes"] == row["flash"]
      assert Map.has_key?(result.resp_cookies, "_dawarich_session")
    end
  end

  defp request(method, path, params) do
    query = URI.encode_query(params)
    target = path <> if(query == "", do: "", else: "?" <> query)

    build_conn(method, target)
    |> put_req_header("accept", "text/html")
    |> AchievementPublicPage.call([])
  end

  defp seed(row) do
    id = row["owner_id"]

    unless rows("SELECT id FROM users WHERE id=$1", [id]) != [] do
      RailsUser.insert!(%{
        id: id,
        email: "public-page-#{id}@example.invalid",
        settings: %{"locale" => row["lang"], "timezone" => "Europe/Berlin"}
      })

      key =
        case row["name"] do
          "continent" -> "continent_europe"
          "flat" -> "country_fr"
          _ -> "country_de"
        end

      codes =
        cond do
          row["locked"] -> []
          row["completed"] -> Registry.find(key).region_codes
          key == "continent_europe" -> ["DE"]
          true -> ["DE-BY"]
        end

      state = %{"earned" => Map.new(codes, &{&1, "2026-10-04T10:00:00Z"})}

      rows(
        "INSERT INTO achievement_progresses(user_id,achievement_key,state,created_at,updated_at) VALUES($1,'exploration',$2,now(),now())",
        [id, state]
      )

      rows(
        "INSERT INTO achievement_progresses(user_id,achievement_key,sharing_enabled,sharing_uuid,state,created_at,updated_at) VALUES($1,$2,true,$3,'{}',now(),now())",
        [id, key, List.last(String.split(row["path"], "/"))]
      )
    end
  end

  defp rows(sql, args \\ []), do: Repo.query!(sql, args, log: false).rows

  defp snapshot,
    do:
      for(
        table <- ~w(users achievement_progresses achievement_unlock_events),
        do: rows("SELECT to_jsonb(t) FROM #{table} t ORDER BY id")
      )
end
