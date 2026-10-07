defmodule DawarichWeb.NullSettingsTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Phoenix.ConnTest
  alias Dawarich.{Repo, UserSettings}
  alias Dawarich.Test.RailsUser

  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    env = Map.take(System.get_env(), ~w(DAWARICH_RAILS SELF_HOSTED TIME_ZONE))
    System.put_env(%{"DAWARICH_RAILS" => "off", "SELF_HOSTED" => "true", "TIME_ZONE" => "UTC"})

    on_exit(fn ->
      for key <- ~w(DAWARICH_RAILS SELF_HOSTED TIME_ZONE) do
        if env[key], do: System.put_env(key, env[key]), else: System.delete_env(key)
      end
    end)

    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)

    user =
      RailsUser.insert!(%{
        id: 49901,
        email: "null-settings@example.invalid",
        api_key: "null-settings-synthetic"
      })

    uuid = "f1000000-0000-4000-8000-000000049901"

    Repo.query!(
      "INSERT INTO achievement_progresses(user_id,achievement_key,state,sharing_enabled,sharing_uuid,created_at,updated_at) VALUES($1,'country_fr','{}',true,$2,now(),now())",
      [user.id, uuid]
    )

    %{user: user}
  end

  test "NULL settings preserve Rails bodies for public HTML PNG map stats timeline settings and API",
       %{user: user} do
    corpus = File.read!("test/fixtures/null_settings.json") |> Jason.decode!()

    pngs =
      for raw <- [nil, :json_null, %{}], row <- corpus do
        if raw == :json_null do
          Repo.query!("UPDATE users SET settings='null'::jsonb WHERE id=$1", [user.id])
        else
          Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [user.id, raw])
        end

        conn =
          cond do
            String.starts_with?(row["path"], "/api/") ->
              build_conn() |> put_req_header("authorization", "Bearer " <> user.api_key)

            String.starts_with?(row["path"], "/shared/") ->
              build_conn()

            true ->
              RailsUser.signed_in(user.id)
          end

        conn = conn |> put_req_header("accept", row["type"]) |> get(row["path"])
        assert conn.status == row["status"], row["path"]

        assert get_resp_header(conn, "content-type") |> hd() |> String.split(";") |> hd() ==
                 row["type"]

        cond do
          row["json"] ->
            assert Jason.decode!(conn.resp_body) == row["json"]

          row["png_header"] ->
            assert conn.resp_body |> :binary.bin_to_list() |> Enum.take(24) == row["png_header"]

          true ->
            doc = LazyHTML.from_document(conn.resp_body)

            for field <- row["selectors"] do
              nodes = LazyHTML.query(doc, field["selector"])

              values =
                if field["attribute"],
                  do: LazyHTML.attribute(nodes, field["attribute"]),
                  else:
                    Enum.map(
                      nodes,
                      &(LazyHTML.text(&1) |> String.replace(~r/\s+/, " ") |> String.trim())
                    )

              assert values == field["values"], row["path"] <> " " <> field["selector"]
            end
        end

        assert Repo.query!("SELECT settings FROM users WHERE id=$1", [user.id]).rows == [
                 [if(raw == :json_null, do: nil, else: raw)]
               ]

        if row["png_header"], do: conn.resp_body
      end

    pngs = Enum.reject(pngs, &is_nil/1)
    assert length(pngs) == 3
    assert length(Enum.uniq(pngs)) == 1
  end

  test "shared user accessor fills absent Rails keys and preserves explicit values" do
    defaults = UserSettings.safe(nil)
    assert UserSettings.provided(nil) == %{}
    assert UserSettings.provided(%{"keep" => true}) == %{"keep" => true}
    assert UserSettings.provided([]) == []
    assert UserSettings.get(%{settings: nil}) == defaults
    assert UserSettings.get(%{}) == defaults
    assert UserSettings.get(%{settings: %{}}) == defaults

    settings = %{
      "maps" => %{"hidden_tile_categories" => ["roads"]},
      "live_map_enabled" => false,
      "route_opacity" => nil,
      "locale" => "de"
    }

    actual = UserSettings.get(%{settings: settings})
    assert actual["maps"] == %{"distance_unit" => "km", "hidden_tile_categories" => ["roads"]}
    assert actual["live_map_enabled"] == false
    assert actual["route_opacity"] == nil
    assert actual["locale"] == "de"
  end
end
