defmodule Dawarich.Achievements.PublicCardTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Achievements.{PublicCard, Registry}
  alias Dawarich.Test.RailsUser

  @at "2026-10-04T10:00:00Z"
  @uuid "a10c0000-0000-4000-8000-000000043101"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Dawarich.Test.AchievementSilhouettes.clear()
    on_exit(&Dawarich.Test.AchievementSilhouettes.clear/0)
    rows("TRUNCATE countries,regions RESTART IDENTITY")
    square = "MULTIPOLYGON (((12.25 51.25,12.25 51.5,12.5 51.5,12.5 51.25,12.25 51.25)))"

    for code <- ~w(DE FR),
        do:
          rows(
            "INSERT INTO countries(iso_a2,iso_a3,name,geom,created_at,updated_at) VALUES($1,$1,$1,ST_GeomFromText($2,4326),now(),now())",
            [code, square]
          )

    :ok
  end

  test "reads only enabled sharing with a live owner and valid definition" do
    seed(43101, "de", %{"earned" => %{"DE-BY" => @at}}, @uuid)
    assert {:ok, _} = PublicCard.load(ScratchRepo, @uuid, %{})
    assert :not_found = PublicCard.load(ScratchRepo, "unknown", %{})

    rows(
      "UPDATE achievement_progresses SET sharing_enabled=false WHERE achievement_key='country_de'"
    )

    assert :not_found = PublicCard.load(ScratchRepo, @uuid, %{})

    rows(
      "UPDATE achievement_progresses SET sharing_enabled=true,achievement_key='missing_definition' WHERE sharing_uuid=$1",
      [@uuid]
    )

    assert :not_found = PublicCard.load(ScratchRepo, @uuid, %{})

    rows(
      "UPDATE achievement_progresses SET achievement_key='border_hopper' WHERE sharing_uuid=$1",
      [@uuid]
    )

    assert {:ok, %{key: "border_hopper"}} = PublicCard.load(ScratchRepo, @uuid, %{})

    rows("UPDATE achievement_progresses SET achievement_key='country_de' WHERE sharing_uuid=$1", [
      @uuid
    ])

    rows("UPDATE users SET locked_at=now() WHERE id=43101")
    assert {:ok, _} = PublicCard.load(ScratchRepo, @uuid, %{})
    rows("UPDATE users SET deleted_at=now() WHERE id=43101")
    assert :not_found = PublicCard.load(ScratchRepo, @uuid, %{})
  end

  test "renders owner locale summary without children or celebration changes" do
    cases =
      "test/fixtures/achievement_public/public.json"
      |> File.read!()
      |> Jason.decode!()
      |> Enum.filter(
        &(&1["name"] in ~w(en_direct de_direct es_direct fr_direct pl_direct ca_direct zh_direct locked completed continent flat))
      )

    for row <- cases do
      id = row["owner_id"]

      key =
        case row["name"] do
          "continent" -> "continent_europe"
          "flat" -> "country_fr"
          _ -> "country_de"
        end

      earned =
        cond do
          row["name"] == "locked" -> %{}
          row["name"] == "completed" -> Map.new(Registry.find(key).region_codes, &{&1, @at})
          key == "continent_europe" -> %{"DE" => @at}
          key == "country_fr" -> %{"FR" => @at}
          true -> %{"DE-BY" => @at}
        end

      seed(id, row["lang"], %{"earned" => earned}, List.last(String.split(row["path"], "/")), key)
      before = snapshot()

      assert {:ok, view} =
               PublicCard.load(ScratchRepo, List.last(String.split(row["path"], "/")), %{
                 locale: "fr"
               })

      assert view.locale == row["lang"]

      assert {view.count, view.target, view.completed, view.locked} ==
               {row["count"], row["target"], row["completed"], row["locked"]}

      assert view.name <> " — Dawarich" == row["title"]
      assert view.description == row["metadata"]["og:description"]
      refute Map.has_key?(view, :children)
      refute Map.has_key?(view, :settings)
      assert snapshot() == before
    end

    rows(
      "UPDATE achievement_progresses SET state='[]'::jsonb WHERE user_id=43001 AND achievement_key='exploration'"
    )

    assert :handoff = PublicCard.load(ScratchRepo, "a10c0000-0000-4000-8000-000000043001", %{})
  end

  test "isolates same-key earned state from other owners and signed-in viewers" do
    seed(43101, "de", %{"earned" => %{"DE-BY" => @at}}, @uuid)
    uuid2 = "a10c0000-0000-4000-8000-000000043102"

    seed(
      43102,
      "en",
      %{"earned" => Map.new(Registry.find("country_de").region_codes, &{&1, @at})},
      uuid2
    )

    RailsUser.insert!(
      %{id: 43103, email: "public-viewer@example.invalid", settings: %{"locale" => "fr"}},
      ScratchRepo
    )

    rows(
      "INSERT INTO achievement_progresses(user_id,achievement_key,state,created_at,updated_at) VALUES(43103,'exploration','{}',now(),now())"
    )

    oracle = "test/fixtures/achievement_public/owners.json" |> File.read!() |> Jason.decode!()
    before = snapshot()

    for {name, uuid} <- [{"first", @uuid}, {"second", uuid2}], viewer <- [nil, 43103] do
      assert {:ok, view} = PublicCard.load(ScratchRepo, uuid, %{viewer_id: viewer, locale: "fr"})
      expected = oracle[name]
      assert view.count == expected["count"]
      assert view.locale == expected["lang"]
      assert view.completed == expected["completed"]
      assert view.description == expected["metadata"]["og:description"]
      assert view.name <> " — Dawarich" == expected["title"]
      refute inspect(view) =~ "example.invalid"
      assert snapshot() == before
    end
  end

  defp seed(id, locale, state, uuid, key \\ "country_de") do
    RailsUser.insert!(
      %{
        id: id,
        email: "public-#{id}@example.invalid",
        settings: %{"locale" => locale, "timezone" => "Europe/Berlin"}
      },
      ScratchRepo
    )

    rows(
      "INSERT INTO achievement_progresses(user_id,achievement_key,state,created_at,updated_at) VALUES($1,'exploration',$2,now(),now())",
      [id, state]
    )

    rows(
      "INSERT INTO achievement_progresses(user_id,achievement_key,state,sharing_enabled,sharing_uuid,created_at,updated_at) VALUES($1,$2,'{}',true,$3,now(),now())",
      [id, key, uuid]
    )
  end

  defp snapshot,
    do:
      for(
        table <- ~w(users achievement_progresses achievement_unlock_events),
        do: rows("SELECT to_jsonb(t) FROM #{table} t ORDER BY id")
      )
end
