defmodule DawarichWeb.A12f2DClosureTest do
  use ExUnit.Case, async: false
  alias Dawarich.{Repo, Redis}
  alias Dawarich.Settings.{Api, Mobile, Progress}
  alias Dawarich.Areas.Api, as: Areas
  alias Dawarich.Users.ApiRecalculation

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    previous_jwt = System.get_env("JWT_SECRET_KEY")
    System.put_env("JWT_SECRET_KEY", "a12f2d-" <> "synthetic-jwt")

    on_exit(fn ->
      if previous_jwt,
        do: System.put_env("JWT_SECRET_KEY", previous_jwt),
        else: System.delete_env("JWT_SECRET_KEY")
    end)

    start_supervised!(hd(Redis.child_specs()))
    start_supervised!(hd(Redis.cache_child_specs()))

    [[id]] =
      Repo.query!(
        "INSERT INTO users(email,encrypted_password,settings,status,plan,created_at,updated_at) VALUES($1,'','{}',1,1,NOW(),NOW()) RETURNING id",
        ["d-#{Ecto.UUID.generate()}@example.invalid"]
      ).rows

    user = %{
      id: id,
      email: "synthetic@example.invalid",
      settings: %{},
      status: 1,
      plan: 1,
      active_until: nil,
      timezone: "Etc/UTC"
    }

    ctx = %{now: ~U[2026-10-06 12:00:00Z], self_hosted?: true}

    on_exit(fn ->
      Redis.cache_command([
        "DEL",
        "recalculation_pending:#{id}",
        Dawarich.Transportation.RecalculationStatus.key(id),
        Dawarich.Transportation.RecalculationStatus.key(id) <> ":events"
      ])
    end)

    {:ok, user: user, ctx: ctx}
  end

  @tag :a12f2_d_02
  test "API settings preserve safe defaults plan gates strong params tiles validation and producer callbacks",
       %{user: user, ctx: ctx} do
    assert {:ok, 200, body} = invoke(Api, :index, [Repo, user, ctx])
    assert body == oracle("settings_default")["body"]
    settings(user, %{"maps" => %{"name" => "Legacy", "distance_unit" => "km"}})

    params = %{
      "settings" => %{
        "maps" => %{"distance_unit" => "mi"},
        "minutes_between_routes" => 9000,
        "ignored" => true
      }
    }

    assert {:ok, 200, body} = invoke(Api, :update, [Repo, user, params, ctx])
    assert body == oracle("settings_merge")["body"]
    assert persisted(user)["maps"]["name"] == "Legacy"
    refute Map.has_key?(persisted(user), "ignored")

    assert {:error, 422, invalid} =
             Api.update(
               Repo,
               user,
               %{
                 "settings" => %{"maps_maplibre_tiles_url" => "https://tiles.example.invalid/{z}"}
               },
               ctx
             )

    assert invalid == oracle("settings_bad_tiles")["body"]

    for url <- [
          "https://styles.example.invalid/style",
          "/style.json",
          "https://tiles.example.invalid/{z}/{x}/{y}.pbf"
        ] do
      assert {:ok, 200, _} =
               Api.update(Repo, user, %{"settings" => %{"maps_maplibre_tiles_url" => url}}, ctx)
    end

    settings(user, %{})
    lite = %{user | plan: 0}
    cloud = %{ctx | self_hosted?: false}
    assert {:ok, 200, body} = Api.index(Repo, lite, cloud)
    assert body == oracle("settings_lite")["body"]

    assert {:ok, 200, body} =
             Api.update(
               Repo,
               lite,
               %{
                 "settings" => %{
                   "enabled_map_layers" => ["Tracks", "Heatmap"],
                   "globe_projection" => true,
                   "maps" => %{"distance_unit" => "mi", "hidden_tile_categories" => ["water"]},
                   "immich_url" => "https://example.invalid",
                   "maps_maplibre_style" => "custom"
                 }
               },
               cloud
             )

    assert body == oracle("settings_lite_update")["body"]

    [[family]] =
      Repo.query!(
        "INSERT INTO families(name,creator_id,access_until,created_at,updated_at) VALUES('Synthetic',$1,$2,NOW(),NOW()) RETURNING id",
        [user.id, ~N[3026-01-01 00:00:00]]
      ).rows

    Repo.query!(
      "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES($1,$2,1,NOW(),NOW())",
      [family, user.id]
    )

    assert {:ok, 200, %{"settings" => %{"globe_projection" => true}}} =
             Api.update(Repo, lite, %{"settings" => %{"globe_projection" => true}}, cloud)

    settings(user, %{
      "maps" => %{"name" => "Legacy"},
      "mobile" => %{"auto_start" => true},
      "digest_emails_enabled" => true
    })

    assert {:ok, general} =
             Api.general(
               Repo,
               user,
               %{
                 "locale" => "de",
                 "timezone" => "Invalid/Zone",
                 "monthly_digest_emails_enabled" => "false",
                 "news_emails_enabled" => "",
                 "show_supporter_badge" => "0"
               },
               ctx
             )

    assert general["locale"] == "de"
    refute Map.has_key?(general, "timezone")
    refute Map.has_key?(general, "digest_emails_enabled")
    assert general["monthly_digest_emails_enabled"] == false
    assert general["news_emails_enabled"] == nil
    assert general["maps"]["name"] == "Legacy"
    assert general["mobile"]["auto_start"] == true
    assert {:error, 401, _} = Api.update(Repo, %{user | status: 0}, params, ctx)
    assert {:ok, 200, _} = Api.index(Repo, %{user | status: 0}, ctx)
    assert {:error, 402, _} = Api.index(Repo, %{user | status: 3}, ctx)
    settings(user, %{})

    for key <-
          ~w(transportation.user_reclassify stats.full_recalculation achievements.check stats.calculate_month),
        do: Dawarich.Jobs.Ownership.put!(Repo, "command:" <> key, :oban)

    Repo.query!(
      "INSERT INTO stats(user_id,year,month,distance,calculation_version,created_at,updated_at) VALUES($1,2024,1,0,1,NOW(),NOW())",
      [user.id]
    )

    assert {:ok, 200, %{"recalculation_triggered" => true}} =
             Api.update(
               Repo,
               user,
               %{
                 "settings" => %{
                   "timezone" => "Berlin",
                   "enabled_transportation_modes" => ["walking"],
                   "min_minutes_spent_in_city" => 120
                 }
               },
               ctx
             )

    assert kinds(user) ==
             ~w(achievements.check stats.calculate_month stats.full_recalculation transportation.user_reclassify)

    [[version]] =
      Repo.query!("SELECT calculation_version FROM stats WHERE user_id=$1", [user.id]).rows

    assert version == 0

    assert {:ok, 200, %{"recalculation_triggered" => false}} =
             Api.update(
               Repo,
               user,
               %{
                 "settings" => %{
                   "enabled_transportation_modes" => ["walking"],
                   "min_minutes_spent_in_city" => "120"
                 }
               },
               ctx
             )

    assert length(kinds(user)) == 4
    Dawarich.Transportation.RecalculationStatus.start(user.id, 2, ctx.now)

    assert {:error, 423, %{"status" => "locked"}} =
             Api.update(
               Repo,
               user,
               %{"settings" => %{"enabled_transportation_modes" => ["driving"]}},
               ctx
             )

    Dawarich.Transportation.RecalculationStatus.clear(user.id)

    assert {:error, 422, _} =
             Api.update(
               Repo,
               user,
               %{"settings" => %{"enabled_transportation_modes" => ["invented"]}},
               ctx
             )
  end

  @tag :a12f2_d_03
  test "Mobile settings and progress preserve timestamp compare and set conflicts and source active guards",
       %{user: user, ctx: ctx} do
    assert {:ok, 200, body} = invoke(Mobile, :show, [Repo, user, ctx])
    assert body == oracle("mobile_default")["body"]

    assert {:ok, 200, body} =
             invoke(Mobile, :update, [
               Repo,
               user,
               %{
                 "settings" => %{
                   "tracking_mode" => "precise",
                   "distance_filter" => 0,
                   "batch_size" => 9000,
                   "tracking_visits" => "false",
                   "unknown" => true
                 },
                 "expected_updated_at" => "stale"
               },
               ctx
             ])

    assert body == oracle("mobile_update")["body"]

    assert {:ok, 200, body} =
             Mobile.update(
               Repo,
               user,
               %{
                 "settings" => %{
                   "time_filter" => 9000,
                   "tracking_mode" => "bad",
                   "distance_filter" => nil
                 }
               },
               ctx
             )

    assert body == oracle("mobile_merge")["body"]
    assert body["settings"]["tracking_mode"] == "precise"
    assert persisted(user)["mobile"]["distance_filter"] == 1
    assert {:ok, 200, _} = Mobile.show(Repo, %{user | status: 0}, ctx)

    assert {:error, 401, _} =
             Mobile.update(
               Repo,
               %{user | status: 0},
               %{"settings" => %{"auto_start" => true}},
               ctx
             )

    assert {:ok, 200, body} = invoke(Progress, :show, [user, ctx])
    assert body == oracle("progress_idle")["body"]
    Dawarich.Transportation.RecalculationStatus.start(user.id, 2, ctx.now)

    assert {:ok, 200, %{"status" => "processing", "total_tracks" => 2, "processed_tracks" => 0}} =
             Progress.show(user, ctx)

    assert {:error, 401, _} = Progress.show(%{user | status: 0}, ctx)
  end

  @tag :a12f2_d_04
  test "Areas API preserves own records geometry Ruby coercions validation and callback effects",
       %{user: user, ctx: ctx} do
    assert {:ok, 200, []} = invoke(Areas, :index, [Repo, user, ctx])
    Dawarich.Jobs.Ownership.put!(Repo, "command:areas.relabel_visits", :oban)

    assert {:error, 422, body} =
             invoke(Areas, :create, [
               Repo,
               user,
               %{"area" => %{"name" => "", "latitude" => 91, "longitude" => 181, "radius" => 0}},
               ctx
             ])

    assert body == oracle("area_invalid")["body"]

    params = %{
      "area" => %{
        "name" => "雪",
        "latitude" => "52.52",
        "longitude" => "13.405",
        "radius" => "100",
        "user_id" => 0
      }
    }

    assert {:ok, 201, area} = Areas.create(Repo, user, params, ctx)
    assert area["latitude"] == "52.52"
    assert area["longitude"] == "13.405"
    assert area["radius"] == 100
    assert area["user_id"] == user.id
    assert kinds(user) == []
    assert count_area_jobs(area["id"]) == 1

    assert {:ok, 200, updated} =
             Areas.update(Repo, user, area["id"], %{"area" => %{"name" => "Renamed"}}, ctx)

    assert updated["name"] == "Renamed"
    assert count_area_jobs(area["id"]) == 1
    foreign = %{user | id: user.id + 1}

    assert {:error, 404, _} =
             Areas.update(Repo, foreign, area["id"], %{"area" => %{"name" => "Stolen"}}, ctx)

    assert {:error, 404, _} = Areas.show(Repo, foreign, area["id"], ctx)
    assert {:error, 404, _} = Areas.destroy(Repo, foreign, area["id"], ctx)

    assert {:ok, 200, _} =
             Areas.update(Repo, user, area["id"], %{"area" => %{"radius" => 200}}, ctx)

    assert count_area_jobs(area["id"]) == 1
    assert {:ok, 200, _} = Areas.index(Repo, %{user | status: 0}, ctx)
    assert {:ok, 200, _} = Areas.destroy(Repo, user, area["id"], ctx)
    assert {:error, 404, _} = Areas.show(Repo, user, area["id"], ctx)
  end

  @tag :a12f2_d_07
  test "API recalculation preserves optional year write entitlement in progress conflict and one native request",
       %{user: user, ctx: ctx} do
    assert {:error, 400, body} =
             invoke(ApiRecalculation, :create, [Repo, user, %{"year" => "1999"}, ctx])

    assert body == oracle("recalculation_invalid")["body"]
    Dawarich.Jobs.Ownership.put!(Repo, "command:users.recalculate_data", :oban)
    assert {:ok, 202, _} = ApiRecalculation.create(Repo, user, %{"year" => "2024tail"}, ctx)

    [[payload]] =
      Repo.query!(
        "SELECT payload FROM job_outbox WHERE command_type='users.recalculate_data' AND aggregate_id=$1",
        [user.id]
      ).rows

    assert payload["year"] == 2024
    assert payload["notify"] == true
    assert {:ok, _} = Dawarich.Users.RecalculateWorker.args_from_command(1, payload)
    assert {:error, 409, body} = ApiRecalculation.create(Repo, user, %{}, ctx)
    assert body == oracle("recalculation_pending")["body"]
    assert kinds(user) == ["users.recalculate_data"]
    assert {:ok, ttl} = Redis.cache_command(["TTL", "recalculation_pending:#{user.id}"])
    assert ttl in 1790..1800
    Redis.cache_command(["DEL", "recalculation_pending:#{user.id}"])
    assert {:ok, 202, _} = ApiRecalculation.create(Repo, user, %{}, ctx)

    payloads =
      Repo.query!(
        "SELECT payload FROM job_outbox WHERE command_type='users.recalculate_data' AND aggregate_id=$1",
        [user.id]
      ).rows
      |> List.flatten()

    assert Enum.frequencies_by(payloads, & &1["year"]) == %{nil => 1, 2024 => 1}
    assert {:error, 401, _} = ApiRecalculation.create(Repo, %{user | status: 0}, %{}, ctx)

    assert {:error, 403, _} =
             ApiRecalculation.create(Repo, %{user | plan: 0}, %{}, %{ctx | self_hosted?: false})
  end

  @tag :a12f2_d_08
  test "Committed domain API effects remain terminal when later invalidation enqueue or rendering fails",
       %{user: user, ctx: ctx} do
    failure = Map.put(ctx, :invalidate_photos, fn _ -> raise "synthetic cache failure" end)

    assert {:error, 500, _} =
             invoke(Api, :update, [
               Repo,
               user,
               %{"settings" => %{"immich_url" => "https://example.invalid/"}},
               failure
             ])

    assert persisted(user)["immich_url"] == "https://example.invalid"
    assert Repo.query!("SELECT count(*) FROM phoenix.rails_commands", []).rows == [[0]]
    Dawarich.Jobs.Ownership.put!(Repo, "command:transportation.user_reclassify", :oban)
    failure = Map.put(ctx, :after_commit, fn -> raise "synthetic render failure" end)

    assert {:error, 500, _} =
             Api.update(
               Repo,
               user,
               %{"settings" => %{"enabled_transportation_modes" => ["walking"]}},
               failure
             )

    assert persisted(user)["enabled_transportation_modes"] == ["walking"]
    assert kinds(user) == ["transportation.user_reclassify"]

    assert {:error, 500, _} =
             Mobile.update(Repo, user, %{"settings" => %{"auto_start" => true}}, failure)

    assert persisted(user)["mobile"]["auto_start"] == true
    Dawarich.Jobs.Ownership.put!(Repo, "command:areas.relabel_visits", :oban)

    assert {:error, 500, _} =
             Areas.create(
               Repo,
               user,
               %{
                 "area" => %{
                   "name" => "Committed",
                   "latitude" => 52,
                   "longitude" => 13,
                   "radius" => 100
                 }
               },
               failure
             )

    assert Repo.query!("SELECT name FROM areas WHERE user_id=$1", [user.id]).rows == [
             ["Committed"]
           ]

    Dawarich.Jobs.Ownership.put!(Repo, "command:users.recalculate_data", :oban)
    assert {:error, 500, _} = ApiRecalculation.create(Repo, user, %{}, failure)
    assert Enum.count(kinds(user), &(&1 == "users.recalculate_data")) == 1
    assert {:error, 409, _} = ApiRecalculation.create(Repo, user, %{}, ctx)
    assert Repo.query!("SELECT count(*) FROM phoenix.rails_commands", []).rows == [[0]]
  end

  defp invoke(module, function, args) do
    if Code.ensure_loaded?(module) and function_exported?(module, function, length(args)),
      do: apply(module, function, args),
      else: :unimplemented
  end

  defp settings(user, value),
    do: Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [user.id, value])

  defp persisted(user),
    do: Repo.query!("SELECT settings FROM users WHERE id=$1", [user.id]).rows |> hd() |> hd()

  defp kinds(user),
    do:
      Repo.query!(
        "SELECT command_type FROM job_outbox WHERE aggregate_id=$1 ORDER BY command_type",
        [user.id]
      ).rows
      |> List.flatten()

  defp count_area_jobs(id),
    do:
      Repo.query!(
        "SELECT count(*) FROM job_outbox WHERE command_type='areas.relabel_visits' AND aggregate_id=$1",
        [id]
      ).rows
      |> hd()
      |> hd()

  defp oracle(name),
    do:
      Path.expand("../fixtures/a12f2d/closure.json", __DIR__)
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!(name)
end
