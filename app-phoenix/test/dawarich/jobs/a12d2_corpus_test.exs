defmodule Dawarich.Jobs.A12d2CorpusTest do
  use Dawarich.JobsCase
  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Integrations.SyncScheduling
  alias Dawarich.Achievements.{BulkCheck, BulkCheckWorker}
  alias Dawarich.Tracks.BackfillWorker
  @oban __MODULE__.Oban
  @now ~U[2026-10-04 12:00:00Z]
  @slot 1_791_115_200

  setup :prepare_corpus

  defp prepare_corpus(%{corpus_case: true}) do
    if rows("SELECT EXISTS(SELECT 1 FROM places)") == [[true]] do
      Dawarich.ScratchCase.recreate_public!(ScratchRepo)
      Dawarich.JobsCase.reset!(ScratchRepo)
    end

    start_oban(@oban)
    start_supervised!(hd(Dawarich.Redis.child_specs()))
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    start_supervised!(Dawarich.Geocoding.FakeHttp)
    previous = System.get_env("SELF_HOSTED")

    on_exit(fn ->
      Dawarich.Geocoding.HookRepo.clear_hook()
      clean_corpus_places()

      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    :ok
  end

  defp prepare_corpus(_), do: :ok

  @corpus Jason.decode!(File.read!("test/fixtures/a12d2/jobs.json"))
  126 = Enum.sum(for {_, entry} <- @corpus["classes"], do: length(entry["cases"]))

  for {name, entry} <- @corpus["classes"], row <- entry["cases"] do
    @name name
    @row row
    @tag :corpus_case
    test "native residual effects match source corpus: #{name}/#{row["id"]}" do
      name = @name
      row = @row
      clean_corpus_places()
      System.put_env("SELF_HOSTED", "false")
      Dawarich.Geocoding.HookRepo.clear_hook()
      actual = native_projection(name, row)
      expected = source_projection(name, row)

      differing = Enum.filter(Map.keys(expected), &(actual[&1] != expected[&1]))

      assert actual == expected,
             "#{name}/#{row["id"]}: #{inspect(Map.take(actual, differing), limit: 15)} != #{inspect(Map.take(expected, differing), limit: 15)}"
    end
  end

  defp clean_corpus_places do
    ids = Enum.to_list(49000..50999) ++ [48201, 48202, 48203]
    rows("DELETE FROM visits WHERE place_id=ANY($1)", [ids])
    rows("DELETE FROM place_visits WHERE place_id=ANY($1)", [ids])
    rows("DELETE FROM taggings WHERE taggable_type='Place' AND taggable_id=ANY($1)", [ids])
    rows("DELETE FROM places WHERE id=ANY($1)", [ids])
  end

  defp native_projection(name, row) do
    {:ok, now, _} = DateTime.from_iso8601(row["now"])
    Process.put(:corpus_zone, row["ambient_zone"])
    Process.put(:corpus_row, row)
    Process.put(:corpus_calls, [])
    Process.put(:corpus_jobs, [])
    Process.put(:corpus_reported, [])

    case name do
      "Achievements::BulkCheckJob" -> replay_achievements(row, now)
      "AirTrail::SyncSchedulingJob" -> replay_scheduler(:airtrail, row, now)
      "TeslaMate::SyncSchedulingJob" -> replay_scheduler(:teslamate, row, now)
      "Trek::SyncSchedulingJob" -> replay_scheduler(:trek, row, now)
      "Tracks::BackfillGenerationJob" -> replay_range(row, now)
      "Tracks::ThrottledBackfillJob" -> replay_walk(row, now)
      "Families::AutoCreationJob" -> replay_auto(row, now)
      "Families::MemberSyncJob" -> replay_members(row, now)
      "Places::NameFetchingJob" -> replay_name(row, now)
      "Places::BulkNameFetchingJob" -> replay_names(row, now)
      "Places::DeleteIfOrphanJob" -> replay_orphan(false, row, now)
      "Places::OrphanCleanupJob" -> replay_orphan(true, row, now)
    end
  end

  defp source_projection(name, row) do
    projection = Map.drop(row, ~w(id now ambient_zone owner sentinel_owner input))

    cond do
      name == "Tracks::ThrottledBackfillJob" and row["id"] == "repeat" ->
        projection
        |> Map.update!("jobs", &Enum.uniq/1)
        |> Map.update!("generation_calls", &Enum.uniq/1)

      name == "Tracks::ThrottledBackfillJob" and row["id"] == "error" ->
        Map.put(projection, "ttl", 43200)

      true ->
        projection
    end
  end

  defp effects(fun) do
    try do
      result = fun.()
      %{"result" => result, "error" => nil, "reported" => Process.get(:corpus_reported)}
    rescue
      e in RuntimeError ->
        %{
          "result" => nil,
          "error" => %{"class" => "RuntimeError", "message" => e.message},
          "reported" => Process.get(:corpus_reported)
        }

      e in Postgrex.Error ->
        %{
          "result" => nil,
          "error" => %{
            "class" => "ActiveRecord::InvalidForeignKey",
            "message" => e.postgres.message
          },
          "reported" => []
        }
    end
  end

  defp iso(nil), do: nil
  defp iso(%DateTime{} = at), do: iso(DateTime.to_naive(at))

  defp iso(%NaiveDateTime{} = at) do
    Dawarich.RailsTime.with_zone(ScratchRepo, Process.get(:corpus_zone), fn ->
      [[text]] =
        rows(
          "SELECT " <> String.replace(Dawarich.RailsTime.sql("$1::timestamp", 3), ".MS", ".US"),
          [at]
        )

      text
    end)
  end

  defp seed_user(id, attrs \\ %{}) do
    settings = Map.get(attrs, :settings, %{"timezone" => "Asia/Tokyo", "locale" => "de"})
    until = Map.get(attrs, :until, ~N[3026-10-04 13:00:00.000000])

    rows(
      "INSERT INTO users(id,email,status,plan,subscription_source,active_until,settings,points_count,created_at,updated_at) VALUES($1,$2,$3,$4,$5,$6,$7,0,now(),now())",
      [
        id,
        "a12d2-corpus-#{id}@example.test",
        Map.get(attrs, :status, 1),
        Map.get(attrs, :plan, 1),
        Map.get(attrs, :source, 0),
        until,
        settings
      ]
    )
  end

  defp seed_point(id, user, timestamp, anomaly \\ false, geometry \\ "POINT(13 52)") do
    rows(
      "INSERT INTO points(id,user_id,timestamp,anomaly,lonlat,created_at,updated_at) VALUES($1,$2,$3,$4,ST_GeomFromText($5,4326),now(),now())",
      [id, user, timestamp, anomaly, geometry]
    )
  end

  defp seed_family(id, creator, until, name \\ "Synthetic family") do
    rows(
      "INSERT INTO families(id,creator_id,access_until,name,created_at,updated_at) VALUES($1,$2,$3,$4,now(),now())",
      [id, creator, until, name]
    )
  end

  defp membership(id, family, user, role \\ 1) do
    rows(
      "INSERT INTO family_memberships(id,family_id,user_id,role,created_at,updated_at) VALUES($1,$2,$3,$4,now(),now())",
      [id, family, user, role]
    )
  end

  defp job(klass, queue, args, due \\ 0),
    do: %{"class" => klass, "queue" => queue, "arguments" => args, "due_offset" => due}

  defp sorted_jobs(jobs),
    do:
      Enum.sort_by(
        jobs,
        &{&1["due_offset"], &1["class"], Dawarich.RubyJson.encode_exact!(&1["arguments"])}
      )

  defp reverse_jobs(row, now) do
    rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id")
    |> Enum.map(fn
      ["integrations.airtrail_flights", p] ->
        job("AirTrail::ImportFlightsJob", "imports", [p["user_id"]])

      ["integrations.teslamate_sync", p] ->
        job("TeslaMate::SyncJob", "imports", [p["user_id"]])

      ["integrations.trek_sync", p] ->
        job("Trek::SyncJob", "imports", [p["source_id"]])

      ["achievements.bulk_check_leaf", p] ->
        job(
          "Achievements::CheckJob",
          "achievements",
          [p["user_id"], %{"notify" => p["notify"], "force" => row["input"]["options"]["force"]}],
          DateTime.diff(parse(p["run_at"]), now)
        )

      ["place_name_fetch", p] ->
        job("Places::NameFetchingJob", "places", [p["place_id"]])

      ["mail.family_lapse", p] ->
        job("Families::LapseNotificationJob", "families", [p["user_id"], p["family_id"]])
    end)
    |> sorted_jobs()
  end

  defp parse(text) do
    {:ok, at, _} = DateTime.from_iso8601(text)
    at
  end

  defp replay_achievements(row, now) do
    input = row["input"]

    for {id, status} <- [{48101, 1}, {48102, 0}, {48103, 2}, {48104, 1}, {48105, 1}, {48106, 1}],
        do: seed_user(id, %{status: status})

    rows("UPDATE users SET deleted_at=$1 WHERE id=48106", [DateTime.to_naive(now)])

    for {id, user} <- [{48301, 48101}, {48302, 48102}, {48303, 48103}, {48304, 48106}],
        do: seed_point(id, user, DateTime.to_unix(now) - 3600)

    seed_point(48305, 48104, DateTime.to_unix(now) - 3600, true)
    seed_point(48306, 48105, DateTime.to_unix(now) - 3600, false, nil)

    for {id, version} <- [{48101, 3}, {48103, 0}],
        do:
          rows(
            "INSERT INTO achievement_progresses(user_id,achievement_key,state,created_at,updated_at) VALUES($1,'exploration',$2,now(),now())",
            [id, %{"calculation_version" => version}]
          )

    if input["extra_eligible_users"] > 0 do
      for id <- 49000..49399 do
        seed_user(id)
        seed_point(id, id, DateTime.to_unix(now) - 3600)
      end
    end

    hook = fn _ -> if row["id"] == "error", do: raise("fixture check publication failure") end

    result =
      effects(fn ->
        for _ <- 1..if(row["id"] == "repeat", do: 2, else: 1) do
          args = Map.put(input["options"], "event_id", Ecto.UUID.generate())

          assert BulkCheck.run(Dawarich.Geocoding.HookRepo, @oban, args, now: now, hook: hook) ==
                   :ok
        end

        nil
      end)

    Map.put(result, "jobs", reverse_jobs(row, now))
  end

  defp replay_scheduler(kind, row, now) do
    seed_user(48101, %{status: 0})
    seed_user(48102, %{status: 0, plan: 0})

    if kind == :trek do
      rows("UPDATE users SET status=1 WHERE id=48101")

      for {id, user, status, provider} <- [
            {48701, 48101, 0, "trek"},
            {48702, 48102, 0, "trek"},
            {48703, 48101, 1, "trek"},
            {48704, 48101, 0, "other"}
          ] do
        source(id, user)
        rows("UPDATE trip_sources SET status=$2,provider=$3 WHERE id=$1", [id, status, provider])
      end

      if row["id"] == "inherited" do
        seed_user(48103, %{plan: 2})
        seed_family(48401, 48103, DateTime.to_naive(DateTime.add(now, 86400)))
        membership(48501, 48401, 48101)
        rows("UPDATE users SET plan=0 WHERE id=48101")
      end

      if row["id"] == "self_hosted", do: System.put_env("SELF_HOSTED", "true")
    else
      settings =
        if kind == :airtrail,
          do: %{
            "airtrail_url" => "https://synthetic.example.test",
            "airtrail_api_key" => "synthetic"
          },
          else: %{"teslamate_url" => "https://synthetic.example.test"}

      rows("UPDATE users SET settings=$2 WHERE id=$1", [48101, settings])

      blank =
        if kind == :airtrail,
          do: Map.put(settings, "airtrail_api_key", ""),
          else: Map.put(settings, "teslamate_url", "")

      rows("UPDATE users SET settings=$2 WHERE id=$1", [48102, blank])
      seed_user(48103, %{settings: Map.new(settings, fn {k, _} -> {k, nil} end)})

      if kind == :airtrail,
        do: seed_user(48104, %{settings: Map.put(settings, "airtrail_url", "")})
    end

    if row["id"] == "batches" do
      [[settings]] = rows("SELECT settings FROM users WHERE id=48101")

      for id <- 49000..50999 do
        seed_user(id, %{settings: settings, status: if(kind == :trek, do: 1, else: 0)})
        if kind == :trek, do: source(id, id)
      end
    end

    Ownership.put!(ScratchRepo, SyncScheduling.key(kind), :oban)
    hook = fn _ -> if row["id"] == "error", do: raise("fixture leaf publication failure") end

    result =
      effects(fn ->
        for slot <- @slot..(@slot + if(row["id"] == "repeat", do: 1, else: 0)) do
          assert SyncScheduling.run(ScratchRepo, @oban, kind, slot, now: now, hook: hook) == :ok
        end

        nil
      end)

    Map.put(result, "jobs", reverse_jobs(row, now))
  end

  defp logged_effects(fun, mappings) do
    log = ExUnit.CaptureLog.capture_log(fn -> Process.put(:corpus_effect, effects(fun)) end)

    Map.put(
      Process.get(:corpus_effect),
      "reported",
      Enum.flat_map(mappings, fn {marker, klass} ->
        if String.contains?(log, marker), do: [klass], else: []
      end)
    )
  end

  defp replay_auto(row, now) do
    profile = row["id"]

    seed_user(48101, %{
      plan: if(profile == "lite", do: 0, else: 2),
      settings: row["input"]["settings"]
    })

    seed_user(48102, %{plan: 0})
    if profile == "missing_user", do: rows("DELETE FROM users WHERE id=48101")

    if profile == "deleted_user",
      do: rows("UPDATE users SET deleted_at=$1 WHERE id=48101", [DateTime.to_naive(now)])

    if profile == "self_hosted", do: System.put_env("SELF_HOSTED", "true")

    if profile in ["existing_member", "existing_creator"] do
      seed_family(48401, 48101, nil)
      if profile == "existing_member", do: membership(48501, 48401, 48101, 0)
    end

    rows("SELECT setval('families_id_seq',48500,false)")

    Dawarich.Geocoding.HookRepo.set_hook(fn sql, _ ->
      cond do
        profile == "creation_error" and String.starts_with?(sql, "INSERT INTO families") ->
          raise "fixture creation failure"

        profile == "notice_error" and String.starts_with?(sql, "INSERT INTO notifications") ->
          raise "fixture notice failure"

        true ->
          :ok
      end
    end)

    hook = fn stage ->
      if stage == :shared and profile in ["error", "sync_error"],
        do: raise("fixture sync failure")
    end

    result =
      logged_effects(
        fn ->
          for _ <- 1..if(profile == "repeat", do: 2, else: 1),
              do:
                Dawarich.Families.AutoCreate.run(Dawarich.Geocoding.HookRepo, 48101,
                  now: now,
                  time_zone: row["ambient_zone"],
                  hook: hook
                )

          nil
        end,
        [
          {"Family creation failed:", "RuntimeError"},
          {"Family auto-creation notice failed:", "RuntimeError"}
        ]
      )

    families =
      rows(
        "SELECT id,creator_id,name,access_until FROM families WHERE creator_id=48101 ORDER BY id"
      )
      |> Enum.map(fn [id, user, name, at] -> [id, user, name, iso(at)] end)

    memberships =
      rows(
        "SELECT family_id,user_id,role FROM family_memberships WHERE user_id=48101 ORDER BY id"
      )
      |> Enum.map(fn [f, u, r] -> [f, u, Enum.at(["owner", "member"], r)] end)

    settings =
      case rows("SELECT settings FROM users WHERE id=48101 AND deleted_at IS NULL") do
        [[s]] -> s
        [] -> nil
      end

    notices =
      rows("SELECT kind,title,content FROM notifications WHERE user_id=48101 ORDER BY id")
      |> Enum.map(fn [k, t, c] -> [Enum.at(["info", "success", "warning", "error"], k), t, c] end)

    [[foreign]] = rows("SELECT EXISTS(SELECT 1 FROM family_memberships WHERE user_id=48102)")

    Map.merge(result, %{
      "jobs" => [],
      "families" => families,
      "memberships" => memberships,
      "settings" => settings,
      "notifications" => notices,
      "foreign_family" => foreign
    })
  end

  defp replay_members(row, now) do
    profile = row["id"]
    seed_user(48101, %{plan: 2, until: DateTime.to_naive(DateTime.add(now, 172_800))})
    seed_user(48102, %{plan: 0, status: 0, until: DateTime.to_naive(DateTime.add(now, -86400))})
    seed_user(48103, %{plan: 1, source: 1})
    seed_family(48401, 48101, DateTime.to_naive(DateTime.add(now, 86400)))

    for {id, user, role} <- [{48501, 48101, 0}, {48502, 48102, 1}, {48503, 48103, 1}],
        do: membership(id, 48401, user, role)

    if profile == "lapse", do: rows("UPDATE users SET subscription_source=2 WHERE id=48102")

    if profile in ["grant", "marked"] do
      [[settings]] = rows("SELECT settings FROM users WHERE id=48102")
      marker = String.replace(iso(now), ".000000", "")

      rows("UPDATE users SET settings=$1 WHERE id=48102", [
        Map.put(settings, "family", %{"plan_lapse_notified_at" => marker})
      ])
    end

    if profile in ["lapse", "marked", "notify_false", "error", "member_error"] do
      period = DateTime.to_naive(DateTime.add(now, -172_800))
      rows("UPDATE users SET active_until=$1 WHERE id=48101", [period])
      rows("UPDATE families SET access_until=$1 WHERE id=48401", [period])
    end

    if profile == "nil_owner_date", do: rows("UPDATE users SET active_until=NULL WHERE id=48101")

    if profile == "downgrade",
      do:
        rows("UPDATE users SET plan=1,active_until=$1 WHERE id=48101", [
          DateTime.to_naive(DateTime.add(now, 432_000))
        ])

    if profile == "self_hosted", do: System.put_env("SELF_HOSTED", "true")

    Dawarich.Geocoding.HookRepo.set_hook(fn sql, _ ->
      cond do
        profile == "member_error" and String.starts_with?(sql, "UPDATE users SET plan = 0") ->
          raise "fixture member failure"

        profile == "error" and String.starts_with?(sql, "INSERT INTO phoenix.rails_commands") ->
          raise "fixture mail publication failure"

        true ->
          :ok
      end
    end)

    result =
      effects(fn ->
        for _ <- 1..if(profile == "repeat", do: 2, else: 1),
            do:
              Dawarich.Families.MemberSync.run(
                Dawarich.Geocoding.HookRepo,
                if(profile == "missing_family", do: 0, else: 48401),
                now: now,
                notify: profile != "notify_false",
                time_zone: row["ambient_zone"]
              )

        nil
      end)

    [[until]] = rows("SELECT access_until FROM families WHERE id=48401")

    members =
      rows(
        "SELECT id,plan,status,active_until,subscription_source,settings FROM users ORDER BY id"
      )
      |> Enum.map(fn [id, p, s, u, source, settings] ->
        %{
          "id" => id,
          "plan" => Enum.at(["lite", "pro", "family"], p),
          "status" => Enum.at(["inactive", "active", "trial", "pending_payment"], s),
          "active_until" => iso(u),
          "subscription_source" =>
            Enum.at(["none", "paddle", "apple_iap", "google_play"], source),
          "settings" => settings
        }
      end)

    Map.merge(result, %{
      "jobs" => reverse_jobs(row, now),
      "access_until" => iso(until),
      "members" => members
    })
  end

  defp replay_range(row, now) do
    profile = row["id"]
    seed_user(48101)
    seed_user(48102)

    if profile == "deleted_user",
      do: rows("UPDATE users SET deleted_at=$1 WHERE id=48101", [DateTime.to_naive(now)])

    if profile == "missing_user", do: rows("DELETE FROM users WHERE id=48101")
    Ownership.put!(ScratchRepo, "command:tracks.backfill", :oban)
    timestamps = row["input"]["timestamps"]
    historical = DateTime.to_unix(now) - if(profile == "berlin_dst", do: 86400, else: 172_800)

    Dawarich.Tracks.BackfillCommands.put(ScratchRepo, 48102, [historical - 86400],
      now: now,
      time_zone: row["ambient_zone"]
    )

    source_range = nil
    Process.put(:range_before, source_range)

    result =
      logged_effects(
        fn ->
          for occurrence <- 1..if(profile == "repeat", do: 2, else: 1) do
            Dawarich.Tracks.BackfillCommands.put(ScratchRepo, 48101, timestamps,
              now: now,
              time_zone: row["ambient_zone"]
            )

            if profile == "merge",
              do:
                Dawarich.Tracks.BackfillCommands.put(
                  ScratchRepo,
                  48101,
                  [historical - 86400, historical + 7200],
                  now: now,
                  time_zone: row["ambient_zone"]
                )

            case rows(
                   "SELECT earliest_timestamp,latest_timestamp,cycle_id::text,due_at FROM phoenix.track_backfill_ranges WHERE user_id=48101"
                 ) do
              [[earliest, latest, cycle, due]] ->
                if occurrence == 1, do: Process.put(:range_before, [earliest, latest])

                Process.put(
                  :corpus_jobs,
                  Process.get(:corpus_jobs) ++
                    [
                      job(
                        "Tracks::BackfillGenerationJob",
                        "tracks",
                        [48101],
                        DateTime.diff(as_utc(due), now) * 1.0
                      )
                    ]
                )

                hook = fn :publishing ->
                  if profile == "error", do: raise("fixture publication failure")
                end

                outcome =
                  BackfillWorker.run(
                    ScratchRepo,
                    @oban,
                    %{"user_id" => 48101, "cycle_id" => cycle},
                    now: now,
                    hook: hook
                  )

                if outcome == {:snooze, 60},
                  do:
                    Process.put(
                      :corpus_jobs,
                      Process.get(:corpus_jobs) ++
                        [job("Tracks::BackfillGenerationJob", "tracks", [48101], 60.0)]
                    )

              [] ->
                :ok
            end
          end

          nil
        end,
        [{"Backfill range publication failed:", "RuntimeError"}]
      )

    children =
      rows("SELECT payload FROM phoenix.rails_commands WHERE kind='tracks_generate_range'")
      |> Enum.map(fn [p] ->
        assert p["user_id"] == 48101
        assert p["import_id"] == nil and p["low_priority"] == false

        job("Tracks::ParallelGeneratorJob", "tracks", [
          p["user_id"],
          %{
            "start_at" => iso(parse(p["start_at"])),
            "end_at" => iso(parse(p["end_at"])),
            "mode" => p["mode"],
            "untracked_only" => p["untracked_only"]
          }
        ])
      end)

    {ttl, remaining} =
      case rows(
             "SELECT earliest_timestamp,latest_timestamp,expires_at FROM phoenix.track_backfill_ranges WHERE user_id=48101"
           ) do
        [[a, b, expires]] -> {DateTime.diff(expires, now), Enum.uniq([a, b])}
        [] -> {-2, []}
      end

    [[foreign_first, foreign_last]] =
      rows(
        "SELECT earliest_timestamp,latest_timestamp FROM phoenix.track_backfill_ranges WHERE user_id=48102"
      )

    Map.merge(result, %{
      "jobs" => sorted_jobs(Process.get(:corpus_jobs) ++ children),
      "range" => Process.get(:range_before),
      "range_ttl" => ttl,
      "remaining_range" => remaining,
      "other_range" => Enum.uniq([foreign_first, foreign_last])
    })
  end

  defp replay_walk(row, now) do
    profile = row["id"]
    seed_user(48101)
    seed_user(48102)
    cursor = row["input"]["cursor"]
    last = row["input"]["eligible_maximum"]

    if profile not in ["empty", "backoff_ttl", "missing_user", "deleted_user", "schedule"] do
      seed_point(48301, 48101, last)
      seed_point(48302, 48101, last - 3600)
      seed_point(48303, 48101, cursor)
      seed_point(48304, 48102, cursor - 1)
    end

    if profile == "missing_user", do: rows("DELETE FROM users WHERE id=48101")

    if profile == "deleted_user",
      do: rows("UPDATE users SET deleted_at=$1 WHERE id=48101", [DateTime.to_naive(now)])

    Ownership.put!(ScratchRepo, "command:tracks.throttled_backfill", :oban)
    Ownership.put!(ScratchRepo, "command:tracks.generate_range", :oban)

    rows(
      "INSERT INTO phoenix.track_backfill_walks(user_id,walk_id,state,expires_at,time_zone) VALUES(48102,$1,'backoff',$2,'Europe/Berlin')",
      [Ecto.UUID.dump!(Ecto.UUID.generate()), DateTime.add(now, 1234)]
    )

    sentinel = rows("SELECT * FROM phoenix.track_backfill_walks WHERE user_id=48102")

    result =
      effects(fn ->
        if profile == "schedule" do
          first =
            Dawarich.Tracks.BackfillCommands.schedule(ScratchRepo, 48101,
              now: now,
              time_zone: row["ambient_zone"]
            )

          second =
            Dawarich.Tracks.BackfillCommands.schedule(ScratchRepo, 48101,
              now: now,
              time_zone: row["ambient_zone"]
            )

          assert match?({:inserted, _}, first) and second == :occupied
          ["OK", nil]
        else
          {:ok, {:inserted, walk}} =
            Dawarich.Tracks.BackfillWalks.schedule(
              ScratchRepo,
              48101,
              row["ambient_zone"],
              now,
              fn _ -> :ok end
            )

          current_cursor =
            if profile in ["exact_cursor", "repeat", "scope", "error"], do: cursor, else: nil

          rows(
            "UPDATE phoenix.track_backfill_walks SET cursor_timestamp=$1 WHERE user_id=48101",
            [current_cursor]
          )

          args = %{
            "user_id" => 48101,
            "walk_id" => walk.walk_id,
            "cursor_timestamp" => current_cursor
          }

          hook = fn {:starting, payload} ->
            assert Ecto.UUID.cast(payload["event_id"]) != :error

            call = %{
              "start_at" => iso(parse(payload["start_at"])),
              "end_at" => iso(parse(payload["end_at"])),
              "mode" => payload["mode"],
              "untracked_only" => payload["untracked_only"],
              "job_queue" => if(payload["low_priority"], do: "low_priority", else: nil),
              "event_id" => "00000000-0000-4000-8000-000000480001",
              "user_id" => payload["user_id"]
            }

            Process.put(:corpus_calls, Process.get(:corpus_calls) ++ [call])
            if profile == "error", do: raise("fixture generation failure")
          end

          assert Dawarich.Tracks.ThrottledBackfillWorker.run(ScratchRepo, @oban, args,
                   now: now,
                   hook: hook
                 ) == :ok

          if profile == "repeat",
            do:
              assert(
                Dawarich.Tracks.ThrottledBackfillWorker.run(ScratchRepo, @oban, args,
                  now: now,
                  hook: hook
                ) == :ok
              )

          nil
        end
      end)

    assert rows("SELECT * FROM phoenix.track_backfill_walks WHERE user_id=48102") == sentinel

    ttl =
      case rows("SELECT expires_at FROM phoenix.track_backfill_walks WHERE user_id=48101") do
        [[expires]] -> DateTime.diff(expires, now)
        [] -> -2
      end

    jobs = walk_jobs(now)

    Map.merge(result, %{
      "jobs" => jobs,
      "generation_calls" => Process.get(:corpus_calls),
      "ttl" => ttl,
      "other_key" => "1"
    })
  end

  defp as_utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
  defp as_utc(%DateTime{} = at), do: at

  defp walk_jobs(now) do
    chunks =
      rows(
        "SELECT c.generation_id::text,c.chunk_id,c.start_ts,c.end_ts,c.buffer_start_ts,c.buffer_end_ts,g.user_id,g.low_priority,g.untracked_only,g.import_id FROM phoenix.track_generation_chunks c JOIN phoenix.track_generations g ON g.id=c.generation_id ORDER BY c.chunk_id"
      )
      |> Enum.map(fn [
                       generation,
                       chunk,
                       first,
                       last,
                       buffer_first,
                       buffer_last,
                       user,
                       priority,
                       untracked,
                       import
                     ] ->
        assert priority == true

        assert [[3]] =
                 rows(
                   "SELECT priority FROM oban.oban_jobs WHERE worker='Dawarich.Tracks.ChunkWorker' AND args->>'generation_id'=$1 AND (args->>'chunk_id')::int=$2",
                   [generation, chunk]
                 )

        details = %{
          "chunk_id" => "00000000-0000-4000-8000-000000480001",
          "start_timestamp" => first,
          "end_timestamp" => last,
          "buffer_start_timestamp" => buffer_first,
          "buffer_end_timestamp" => buffer_last,
          "start_time" => iso(DateTime.from_unix!(first)),
          "end_time" => iso(DateTime.from_unix!(last)),
          "buffer_start_time" => iso(DateTime.from_unix!(buffer_first)),
          "buffer_end_time" => iso(DateTime.from_unix!(buffer_last)),
          "untracked_only" => untracked,
          "import_id" => import
        }

        job("Tracks::TimeChunkProcessorJob", "low_priority", [
          user,
          "00000000-0000-4000-8000-000000480001",
          details
        ])
      end)

    boundaries =
      rows(
        "SELECT g.user_id,j.scheduled_at,j.inserted_at,j.priority FROM oban.oban_jobs j JOIN phoenix.track_generations g ON g.id::text=j.args->>'generation_id' WHERE j.worker='Dawarich.Tracks.BoundaryWorker'"
      )
      |> Enum.map(fn [user, due, inserted, priority] ->
        assert priority == 3

        job(
          "Tracks::BoundaryResolverJob",
          "low_priority",
          [user, "00000000-0000-4000-8000-000000480001"],
          round(NaiveDateTime.diff(due, inserted, :microsecond) / 1_000_000) * 1.0
        )
      end)

    successors =
      rows(
        "SELECT args,scheduled_at FROM oban.oban_jobs WHERE worker='Dawarich.Tracks.ThrottledBackfillWorker'"
      )
      |> Enum.map(fn [args, due] ->
        job(
          "Tracks::ThrottledBackfillJob",
          "low_priority",
          [args["user_id"], args["cursor_timestamp"]],
          DateTime.diff(as_utc(due), now) * 1.0
        )
      end)

    initial =
      rows(
        "SELECT payload,scheduled_at FROM job_outbox WHERE command_type='tracks.throttled_backfill'"
      )
      |> Enum.map(fn [p, due] ->
        job(
          "Tracks::ThrottledBackfillJob",
          "low_priority",
          [p["user_id"], p["cursor_timestamp"]],
          DateTime.diff(as_utc(due), now) * 1.0
        )
      end)

    sorted_jobs(chunks ++ boundaries ++ successors ++ initial)
  end

  defp seed_place(id, user, name \\ "Suggested place", source \\ 1, note \\ nil) do
    rows(
      "INSERT INTO places(id,user_id,name,source,note,latitude,longitude,lonlat,created_at,updated_at) VALUES($1,$2,$3,$4,$5,52,13,ST_GeomFromText('POINT(13 52)',4326),now(),now())",
      [id, user, name, source, note]
    )
  end

  defp seed_visit(id, user, place, now, name \\ "Suggested place", status \\ 0, deleted \\ nil) do
    start = DateTime.to_naive(DateTime.add(now, id - 48601))

    rows(
      "INSERT INTO visits(id,user_id,place_id,name,status,deleted_at,started_at,ended_at,duration,created_at,updated_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,3600,now(),now())",
      [id, user, place, name, status, deleted, start, NaiveDateTime.add(start, 3600)]
    )
  end

  defp replay_name(row, now) do
    Process.put(:corpus_missing, false)
    profile = row["id"]
    seed_user(48101)
    seed_user(48102)
    seed_place(48201, 48101, if(profile == "locked", do: "Owner name", else: "Old machine name"))
    seed_place(48202, 48102)

    if profile == "locked",
      do: rows("UPDATE places SET name_locked_at=$1 WHERE id=48201", [DateTime.to_naive(now)])

    seed_visit(48601, 48101, 48201, now)
    seed_visit(48602, 48101, 48201, now, "Custom visit")
    seed_visit(48603, 48101, 48202, now)

    seed_visit(
      48604,
      48101,
      48201,
      now,
      if(profile == "locked", do: "Owner name", else: "Old machine name")
    )

    config =
      Dawarich.Geocoding.Config.resolve(ScratchRepo, %{
        "PHOTON_API_HOST" => "a12d2-#{profile}.example.test",
        "STORE_GEODATA" => if(profile == "geodata_disabled", do: "false", else: "true")
      })

    {url, key, _} =
      Dawarich.Geocoding.Query.build(
        config,
        {52.0, 13.0},
        [limit: 1, distance_sort: true],
        "test"
      )

    Dawarich.Redis.cache_command(["DEL", key])

    data = %{
      "properties" => row["input"]["properties"],
      "geometry" => %{"type" => "Point", "coordinates" => [13, 52]}
    }

    case profile do
      "empty" ->
        Dawarich.Geocoding.FakeHttp.stub(
          url,
          200,
          Jason.encode!(%{"type" => "FeatureCollection", "features" => []})
        )

      "properties_empty" ->
        Dawarich.Geocoding.FakeHttp.stub(
          url,
          200,
          Jason.encode!(%{"type" => "FeatureCollection", "features" => [%{}]})
        )

      "transient" ->
        Dawarich.Geocoding.FakeHttp.stub_error(url, :timeout)

      "tls" ->
        Dawarich.Geocoding.FakeHttp.stub_error(url, :tls)

      p when p in ["unexpected", "error"] ->
        Dawarich.Geocoding.FakeHttp.stub_raise(url)

      _ ->
        Dawarich.Geocoding.FakeHttp.stub(
          url,
          200,
          Jason.encode!(%{"type" => "FeatureCollection", "features" => [data]})
        )
    end

    result =
      logged_effects(
        fn ->
          for _ <- 1..if(profile == "repeat", do: 2, else: 1) do
            outcome =
              Dawarich.Places.NameFetchWorker.run(
                ScratchRepo,
                %{
                  "user_id" => 48101,
                  "place_id" => if(profile == "missing", do: 0, else: 48201),
                  "event_id" => Ecto.UUID.generate()
                },
                config: config
              )

            if outcome == {:error, :not_found}, do: Process.put(:corpus_missing, true)
          end

          nil
        end,
        [{"class=RuntimeError", "StandardError"}]
      )

    result =
      if Process.get(:corpus_missing),
        do:
          Map.put(result, "error", %{
            "class" => "ActiveRecord::RecordNotFound",
            "message" => "Couldn't find Place with 'id'=0"
          }),
        else: result

    [[name, city, country, geodata, source, locked]] =
      rows("SELECT name,city,country,geodata,source,name_locked_at FROM places WHERE id=48201")

    [[foreign]] = rows("SELECT name FROM places WHERE id=48202")

    Map.merge(result, %{
      "jobs" => [],
      "place" => %{
        "id" => 48201,
        "name" => name,
        "city" => city,
        "country" => country,
        "geodata" => geodata,
        "source" => Enum.at(["manual", "photon", "gpx_waypoint"], source),
        "name_locked_at" => iso(locked)
      },
      "visit_names" => rows("SELECT id,name FROM visits ORDER BY id"),
      "foreign_place_name" => foreign
    })
  end

  defp replay_names(row, now) do
    seed_user(48101)
    seed_user(48102)
    seed_place(48201, 48101)
    seed_place(48202, 48102)
    seed_place(48203, 48102, "Custom name")
    if row["id"] == "batches", do: Enum.each(49000..50999, &seed_place(&1, 48101))
    Ownership.put!(ScratchRepo, "command:places.bulk_name_fetch", :oban)
    hook = fn _ -> if row["id"] == "error", do: raise("fixture name publication failure") end

    result =
      effects(fn ->
        for _ <- 1..if(row["id"] == "repeat", do: 2, else: 1),
            do: drain_names(%{"event_id" => Ecto.UUID.generate(), "cursor" => 0}, hook)

        nil
      end)

    Map.put(result, "jobs", reverse_jobs(row, now))
  end

  defp drain_names(args, hook) do
    Dawarich.Places.BulkNameFetchWorker.run(ScratchRepo, @oban, args, hook: hook)

    next =
      rows(
        "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Places.BulkNameFetchWorker' AND args->>'event_id'=$1 AND (args->>'cursor')::bigint>$2 ORDER BY (args->>'cursor')::bigint LIMIT 1",
        [args["event_id"], args["cursor"]]
      )

    case next do
      [[successor]] -> drain_names(successor, hook)
      [] -> :ok
    end
  end

  defp replay_orphan(sweep, row, now) do
    profile = row["id"]
    seed_user(48101)
    seed_user(48102)

    source =
      case profile do
        "manual" -> 0
        "waypoint" -> 2
        _ -> 1
      end

    note =
      case profile do
        "noted" -> "Retain"
        "whitespace_note" -> " "
        _ -> nil
      end

    seed_place(48201, 48101, "Suggested place", source, note)
    seed_place(48202, 48102)

    if profile in ["active", "hidden", "declined"],
      do:
        seed_visit(
          48601,
          48101,
          48201,
          now,
          "Suggested place",
          if(profile == "declined", do: 2, else: 0),
          if(profile == "hidden", do: DateTime.to_naive(now), else: nil)
        )

    if profile == "tagged" do
      rows(
        "INSERT INTO tags(id,user_id,name,created_at,updated_at) VALUES(48801,48101,'Synthetic',now(),now())"
      )

      rows(
        "INSERT INTO taggings(tag_id,taggable_id,taggable_type,created_at,updated_at) VALUES(48801,48201,'Place',now(),now())"
      )
    end

    if profile == "batches", do: Enum.each(49000..49999, &seed_place(&1, 48101))

    if profile == "deleted_user",
      do: rows("UPDATE users SET deleted_at=$1 WHERE id=48101", [DateTime.to_naive(now)])

    Ownership.put!(ScratchRepo, "command:places.orphan_cleanup", :oban)

    Dawarich.Geocoding.HookRepo.set_hook(fn sql, _ ->
      cond do
        profile == "fk" and String.starts_with?(sql, "UPDATE visits SET place_id=NULL") ->
          raise %Postgrex.Error{
            postgres: %{code: :foreign_key_violation, message: "fixture FK failure"}
          }

        profile == "error" and
            (String.starts_with?(sql, "SELECT p.id") or
               String.starts_with?(sql, "SELECT source, note")) ->
          raise "fixture deletion failure"

        true ->
          :ok
      end
    end)

    result =
      effects(fn ->
        if sweep do
          args = %{
            "user_id" => if(profile == "missing_user", do: 0, else: 48101),
            "event_id" => Ecto.UUID.generate(),
            "cursor" => 0
          }

          drain_orphans(args)

          if profile == "repeat",
            do: drain_orphans(Map.put(args, "event_id", Ecto.UUID.generate()))

          nil
        else
          id = row["input"]["place_id"]
          first = Dawarich.Places.Orphans.delete(Dawarich.Geocoding.HookRepo, 48101, id)

          if profile == "repeat",
            do: [first, Dawarich.Places.Orphans.delete(Dawarich.Geocoding.HookRepo, 48101, id)],
            else: first
        end
      end)

    [[place, other, count]] =
      rows(
        "SELECT EXISTS(SELECT 1 FROM places WHERE id=48201),EXISTS(SELECT 1 FROM places WHERE id=48202),(SELECT count(*) FROM places WHERE id>=49000 AND id<50000)"
      )

    Map.merge(result, %{
      "jobs" => [],
      "place_exists" => place,
      "other_place_exists" => other,
      "remaining_batch_places" => count,
      "visit_place_ids" => rows("SELECT place_id FROM visits WHERE id=48601") |> List.flatten()
    })
  end

  defp drain_orphans(args) do
    Dawarich.Places.OrphanCleanupWorker.run(Dawarich.Geocoding.HookRepo, @oban, args)

    next =
      rows(
        "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Places.OrphanCleanupWorker' AND args->>'event_id'=$1 AND (args->>'cursor')::bigint>$2 ORDER BY (args->>'cursor')::bigint LIMIT 1",
        [args["event_id"], args["cursor"]]
      )

    case next do
      [[successor]] -> drain_orphans(successor)
      [] -> :ok
    end
  end

  test "committed publication survives producer failure and release without duplicate unit effects" do
    start_oban(@oban)

    for id <- [48_901, 48_902],
        do:
          user(id, %{
            "airtrail_url" => "https://synthetic.example.test",
            "airtrail_api_key" => "synthetic"
          })

    key = SyncScheduling.key(:airtrail)
    Ownership.put!(ScratchRepo, key, :oban)
    first = SyncScheduling.receipt_id(:airtrail, @slot, 48_901)
    second = SyncScheduling.receipt_id(:airtrail, @slot, 48_902)

    assert SyncScheduling.run(ScratchRepo, @oban, :airtrail, @slot,
             hook: fn id -> if id == 48_902, do: ScratchRepo.rollback(:producer_failed) end
           ) == {:error, :producer_failed}

    refute Processed.done?(ScratchRepo, first)
    refute Processed.done?(ScratchRepo, second)
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    Ownership.put!(ScratchRepo, key, :sidekiq)
    assert SyncScheduling.run(ScratchRepo, @oban, :airtrail, @slot) == {:cancel, :not_owner}
    Ownership.put!(ScratchRepo, key, :oban)
    assert SyncScheduling.run(ScratchRepo, @oban, :airtrail, @slot) == :ok
    assert SyncScheduling.run(ScratchRepo, @oban, :airtrail, @slot) == :ok

    assert rows("SELECT (payload->>'user_id')::bigint FROM phoenix.rails_commands ORDER BY id") ==
             [[48_901], [48_902]]

    Ownership.put!(ScratchRepo, "command:tracks.backfill", :oban)

    assert {:inserted, range} =
             Dawarich.Tracks.BackfillCommands.put(
               ScratchRepo,
               48_901,
               [DateTime.to_unix(@now) - 100_000],
               now: @now,
               time_zone: "Europe/Berlin"
             )

    due = DateTime.add(@now, 60)

    assert_raise RuntimeError, "before acknowledgement", fn ->
      Dawarich.Jobs.Dispatch.run(
        repo: ScratchRepo,
        oban: @oban,
        now: due,
        hook: fn
          :inserted, _ -> raise "before acknowledgement"
          _, _ -> :ok
        end
      )
    end

    assert rows("SELECT state FROM job_outbox") == [["pending"]]
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    Ownership.put!(ScratchRepo, "command:tracks.backfill", :sidekiq)

    assert Dawarich.Jobs.Dispatch.run(repo: ScratchRepo, oban: @oban, now: due) == %{
             dispatched: 1
           }

    assert Dawarich.Jobs.Dispatch.run(repo: ScratchRepo, oban: @oban, now: due) == %{}

    assert BackfillWorker.run(
             ScratchRepo,
             @oban,
             %{"user_id" => 48_901, "cycle_id" => range.cycle_id},
             now: @now
           ) == :ok

    assert BackfillWorker.run(
             ScratchRepo,
             @oban,
             %{"user_id" => 48_901, "cycle_id" => range.cycle_id},
             now: @now
           ) == :ok

    assert rows("SELECT kind FROM phoenix.rails_commands ORDER BY id") == [
             ["integrations.airtrail_flights"],
             ["integrations.airtrail_flights"],
             ["tracks_generate_range"]
           ]

    assert rows(
             "SELECT (payload->>'user_id')::bigint FROM phoenix.rails_commands WHERE kind='tracks_generate_range'"
           ) == [[48_901]]
  end

  @tag :rails_parity
  @tag :a12d2_reverse_handoff
  test "publishes actual reverse rows for the Rails acceptance handoff" do
    assert rows("SELECT max(version::bigint) FROM schema_migrations") == [[20_260_927_120_000]]
    schema_hash = :crypto.hash(:sha, File.read!("../db/schema.rb")) |> Base.encode16(case: :lower)

    for {key, value} <- [{"environment", "test"}, {"schema_sha1", schema_hash}] do
      rows(
        "INSERT INTO ar_internal_metadata(key,value,created_at,updated_at) VALUES($1,$2,now(),now()) ON CONFLICT(key) DO UPDATE SET value=EXCLUDED.value,updated_at=now()",
        [key, value]
      )
    end

    start_oban(@oban)
    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    for id <- [48_801, 48_802] do
      user(id, %{
        "airtrail_url" => "https://airtrail.example.test",
        "airtrail_api_key" => "synthetic",
        "teslamate_url" => "https://teslamate.example.test"
      })

      source(id + 20, id)
    end

    for kind <- [:airtrail, :teslamate, :trek] do
      Ownership.put!(ScratchRepo, SyncScheduling.key(kind), :oban)
      assert SyncScheduling.run(ScratchRepo, @oban, kind, @slot, now: @now) == :ok
    end

    for {id, cycle} <- [
          {48_801, "00000000-0000-4000-8000-000000048801"},
          {48_802, "00000000-0000-4000-8000-000000048802"}
        ] do
      rows(
        "INSERT INTO phoenix.track_backfill_ranges(user_id,earliest_timestamp,latest_timestamp,cycle_id,time_zone,due_at,expires_at) VALUES($1,$2,$3,$4,'Europe/Berlin',$5,$6)",
        [
          id,
          DateTime.to_unix(@now) - 86_400,
          DateTime.to_unix(@now) - 43_200,
          Ecto.UUID.dump!(cycle),
          @now,
          DateTime.add(@now, 21_600)
        ]
      )

      assert BackfillWorker.run(ScratchRepo, @oban, %{"user_id" => id, "cycle_id" => cycle},
               now: @now
             ) == :ok

      assert Processed.done?(ScratchRepo, cycle)
    end

    reverse = rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id")
    assert length(reverse) == 8

    for [kind, payload] <- reverse do
      assert payload["user_id"] in [48_801, 48_802]

      if kind != "tracks_generate_range",
        do: assert(Ecto.UUID.cast(payload["event_id"]) != :error)
    end

    rows("UPDATE users SET settings='{}' WHERE id=ANY($1)", [[48_801, 48_802]])
    rows("UPDATE trip_sources SET status=1 WHERE id=ANY($1)", [[48_821, 48_822]])

    for {kind, first} <- [airtrail: 51_001, teslamate: 53_001, trek: 55_001] do
      for id <- first..(first + 1000) do
        settings =
          case kind do
            :airtrail ->
              %{
                "airtrail_url" => "https://cron-airtrail.example.test",
                "airtrail_api_key" => "synthetic"
              }

            :teslamate ->
              %{"teslamate_url" => "https://cron-teslamate.example.test"}

            :trek ->
              %{}
          end

        user(id, settings)
        if kind == :trek, do: source(id, id)
      end

      key = SyncScheduling.key(kind)
      Ownership.put!(ScratchRepo, key, :oban)
      hook = release_hook(key, first + 999)

      assert SyncScheduling.run(ScratchRepo, @oban, kind, @slot, now: @now, hook: hook) ==
               {:cancel, :not_owner}

      assert_receive {:releasing, task}
      assert Task.await(task) == :ok

      for id <- first..(first + 999) do
        assert Processed.done?(ScratchRepo, SyncScheduling.receipt_id(kind, @slot, id))
      end

      refute Processed.done?(ScratchRepo, SyncScheduling.receipt_id(kind, @slot, first + 1000))
    end

    for id <- 57_001..57_201 do
      user(id, %{})

      rows(
        "INSERT INTO points(user_id,timestamp,lonlat,created_at,updated_at) VALUES($1,1780300000,ST_SetSRID(ST_MakePoint(13,52),4326),now(),now())",
        [id]
      )
    end

    Ownership.put!(ScratchRepo, BulkCheckWorker.key(), :oban)

    assert BulkCheckWorker.run_cron(ScratchRepo, @oban, @slot,
             now: @now,
             hook: achievement_release_hook()
           ) == {:cancel, :not_owner}

    assert_receive {:releasing, task}
    assert Task.await(task) == :ok

    published =
      rows(
        "SELECT (payload->>'user_id')::bigint FROM phoenix.rails_commands WHERE kind='achievements.bulk_check_leaf'"
      )
      |> List.flatten()

    assert length(published) == 200

    for id <- published,
        do:
          assert(Processed.done?(ScratchRepo, BulkCheck.receipt_id(BulkCheck.cron_id(@slot), id)))

    for id <- Enum.to_list(57_001..57_201) -- published,
        do:
          refute(Processed.done?(ScratchRepo, BulkCheck.receipt_id(BulkCheck.cron_id(@slot), id)))

    assert rows(
             "SELECT count(*) FROM phoenix.rails_commands WHERE (payload->>'user_id')::bigint BETWEEN 51001 AND 57201"
           ) == [[3200]]

    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
  end

  defp achievement_release_hook do
    Process.put(:achievement_handoff_count, 0)
    release = release_hook(BulkCheckWorker.key(), nil)

    fn _ ->
      count = Process.get(:achievement_handoff_count) + 1
      Process.put(:achievement_handoff_count, count)
      if count == 200, do: release.(nil)
    end
  end

  defp release_hook(key, last) do
    parent = self()

    fn id ->
      if id == last do
        task = Task.async(fn -> Ownership.put!(ScratchRepo, key, :sidekiq) end)

        assert Dawarich.LockRace.wait_until(fn ->
                 Dawarich.LockRace.blocked("INSERT INTO phoenix.job_owners%") > 0
               end)

        send(parent, {:releasing, task})
      end
    end
  end

  defp user(id, settings),
    do:
      rows(
        "INSERT INTO users(id,email,status,plan,settings,created_at,updated_at) VALUES($1,$2,1,1,$3,now(),now())",
        [id, "a12d2-handoff-#{id}@example.test", settings]
      )

  defp source(id, user),
    do:
      rows(
        "INSERT INTO trip_sources(id,user_id,status,provider,base_url,api_key,created_at,updated_at) VALUES($1,$2,0,'trek',$3,'synthetic',now(),now())",
        [id, user, "https://a12d2-handoff-#{id}.example.test"]
      )
end
