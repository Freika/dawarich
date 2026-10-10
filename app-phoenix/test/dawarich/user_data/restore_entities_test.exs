defmodule Dawarich.UserData.RestoreEntitiesTest do
  use Dawarich.JobsCase
  alias Dawarich.Test.UserDataSeeds
  alias Dawarich.UserData.Restore.{Settings, Areas, Notifications}

  setup do
    rows("DELETE FROM countries WHERE id=988991")

    rows(
      "TRUNCATE places, areas, tags, taggings, visits, tracks, track_segments, digests, points_raw_data_archives CASCADE"
    )

    c = UserDataSeeds.seed!("v2", ScratchRepo)
    expected = UserDataSeeds.entries("export_UTC")

    data =
      Map.new(~w(settings areas notifications), fn name ->
        rows =
          expected[name <> ".jsonl"]
          |> String.split("\n", trim: true)
          |> Enum.map(&Jason.decode!/1)

        {name, if(name == "settings", do: hd(rows), else: rows)}
      end)

    %{c: c, data: data}
  end

  @tag :tmp_dir
  test "restore standalone entities and settings match Rails create counts", %{
    c: c,
    data: data,
    tmp_dir: dir
  } do
    assert Settings.call(ScratchRepo, c.user_id, data["settings"], c.context) ==
             c.expected["result"]["settings_updated"]

    assert [[c.expected["settings"]]] ==
             rows("SELECT settings FROM users WHERE id=$1", [c.user_id])

    assert Areas.call(ScratchRepo, c.user_id, data["areas"], c.context) ==
             c.expected["result"]["areas_created"]

    assert Notifications.call(ScratchRepo, c.user_id, data["notifications"], c.context) ==
             c.expected["result"]["notifications_created"]

    for {module, name} <- [
          {Dawarich.UserData.Export.Areas, "areas"},
          {Dawarich.UserData.Export.Notifications, "notifications"}
        ] do
      [entry] = module.write(ScratchRepo, c.user_id, dir, c.context)

      actual =
        entry.path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

      expected = Enum.reject(c.expected["rows"][name], &(&1["title"] == "Data import completed"))
      assert actual == expected
    end

    assert Areas.call(ScratchRepo, c.user_id, data["areas"], c.context) == 0
    assert Notifications.call(ScratchRepo, c.user_id, data["notifications"], c.context) == 0
    invalid = UserDataSeeds.entries("invalid_entities")

    for {module, name} <- [{Areas, "areas"}, {Notifications, "notifications"}] do
      input =
        invalid[name <> ".jsonl"] |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

      assert module.call(ScratchRepo, c.user_id, input, c.context) == 0
      assert module.call(ScratchRepo, c.user_id, nil, c.context) == 0
    end

    refute Settings.call(ScratchRepo, c.user_id, false, c.context)

    assert Settings.call(
             ScratchRepo,
             c.user_id,
             %{"maps" => %{"only" => true}, "gps_filtering_enabled" => nil},
             c.context
           )

    [[settings]] = rows("SELECT settings FROM users WHERE id=$1", [c.user_id])
    assert settings["retained"] == "yes"
    assert settings["maps"] == %{"only" => true}
    assert settings["gps_filtering_enabled"] == nil
    duplicate = hd(data["areas"]) |> Map.put("name", "duplicate") |> Map.delete("radius")
    assert Areas.call(ScratchRepo, c.user_id, [duplicate, duplicate], c.context) == 2
    assert [[100], [100]] == rows("SELECT radius FROM areas WHERE name='duplicate'")

    note =
      hd(data["notifications"])
      |> Map.put("title", "default kind")
      |> Map.delete("kind")
      |> Map.put("created_at", "")

    assert Notifications.call(ScratchRepo, c.user_id, [note, note], c.context) == 2
    assert [[0], [0]] == rows("SELECT kind FROM notifications WHERE title='default kind'")

    assert Notifications.call(
             ScratchRepo,
             c.user_id,
             [%{note | "title" => " default kind ", "created_at" => "2025-01-01T00:00:00Z"}],
             c.context
           ) == 0

    rows(
      "INSERT INTO stats(user_id,year,month,distance,calculation_version,created_at,updated_at) VALUES($1,2026,1,0,3,$2,$2)",
      [c.user_id, c.context.now]
    )

    context =
      c.context
      |> Map.put(:stats_jitter, fn -> 123 end)
      |> Map.put(:stats_opts, clock: 1_790_942_400)

    assert Settings.call(ScratchRepo, c.user_id, %{"timezone" => "Europe/Berlin"}, context)

    assert [[0, ~N[2026-10-02 12:00:00.000000]]] ==
             rows("SELECT calculation_version,repair_deferred_at FROM stats WHERE user_id=$1", [
               c.user_id
             ])

    assert [[source]] =
             rows(
               "SELECT payload->>'source_job_id' FROM phoenix.rails_commands WHERE kind='stats.calculate_month'"
             )

    assert Ecto.UUID.cast(source) == {:ok, source}

    assert [
             [
               %{
                 "user_id" => c.user_id,
                 "year" => 2026,
                 "month" => 1,
                 "notify_on_failure" => false,
                 "run_at" => 1_790_942_523
               }
             ]
           ] ==
             rows(
               "SELECT payload - 'source_job_id' FROM phoenix.rails_commands WHERE kind='stats.calculate_month'"
             )

    assert {:error, :synthetic_rollback} =
             ScratchRepo.transaction(fn ->
               Settings.call(ScratchRepo, c.user_id, %{"timezone" => "UTC"}, context)
               Areas.call(ScratchRepo, c.user_id, [%{duplicate | "name" => "rollback"}], context)
               ScratchRepo.rollback(:synthetic_rollback)
             end)

    assert [["Europe/Berlin"]] ==
             rows("SELECT settings->>'timezone' FROM users WHERE id=$1", [c.user_id])

    assert [] == rows("SELECT name FROM areas WHERE name='rollback'")
    assert [[1]] == rows("SELECT count(*) FROM phoenix.rails_commands")
    assert [] == rows("SELECT command_type FROM job_outbox")
  end

  test "restore always writes the authenticated target user", %{c: c, data: data} do
    rows(
      "INSERT INTO users(id,email,created_at,updated_at) VALUES(988002,'restore-foreign@example.invalid',$1,$1)",
      [c.context.now]
    )

    context =
      Map.put(c.context, :fence, fn fun ->
        Process.put(:restore_fences, Process.get(:restore_fences, 0) + 1)
        fun.()
      end)

    area = hd(data["areas"]) |> Map.put("user_id", 988_002) |> Map.put("id", 988_111)
    note = hd(data["notifications"]) |> Map.put("user_id", 988_002) |> Map.put("id", 988_112)
    assert Areas.call(ScratchRepo, c.user_id, [area], context) == 1
    assert Notifications.call(ScratchRepo, c.user_id, [note], context) == 1
    assert [[988_111, c.user_id]] == rows("SELECT id,user_id FROM areas")
    assert [[988_112, c.user_id]] == rows("SELECT id,user_id FROM notifications")
    assert Settings.call(ScratchRepo, c.user_id, %{"test" => true}, context)
    assert Process.get(:restore_fences) >= 3
    assert [[0]] == rows("SELECT count(*) FROM areas WHERE user_id=988002")
    assert [[0]] == rows("SELECT count(*) FROM notifications WHERE user_id=988002")
    assert Areas.call(ScratchRepo, c.user_id, [%{area | "name" => "colliding"}], context) == 0
    assert [["Synthetic area"]] == rows("SELECT name FROM areas WHERE id=988111")
  end
end
