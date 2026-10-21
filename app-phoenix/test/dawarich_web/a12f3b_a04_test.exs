defmodule DawarichWeb.A12f3bA04Test do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Achievements.{BulkCheck, CheckWorker}
  alias Dawarich.Jobs.Ownership
  @oban __MODULE__.Oban
  @now ~U[2026-10-04 12:00:00Z]

  setup do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")
    previous_repo = Application.fetch_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")

      case previous_repo do
        {:ok, repo} -> Application.put_env(:dawarich, :jobs_repo, repo)
        :error -> Application.delete_env(:dawarich, :jobs_repo)
      end

      rows("DROP TRIGGER IF EXISTS a12f3b_notice_failure ON notifications")
      rows("DROP FUNCTION IF EXISTS a12f3b_notice_failure()")
    end)

    start_oban(@oban)
    fixture = File.read!("test/fixtures/achievements/check.json") |> Jason.decode!()
    user = fixture["user"]

    rows(
      "INSERT INTO users(id,email,settings,status,created_at,updated_at) VALUES($1,$2,$3,1,now(),now())",
      [user["id"], user["email"], Map.put(user["settings"], "timezone", "Pacific/Chatham")]
    )

    for country <- fixture["countries"],
        do:
          rows(
            "INSERT INTO countries(id,iso_a2,iso_a3,name,geom,created_at,updated_at) SELECT id,iso_a2,iso_a3,name,geom,created_at,updated_at FROM json_populate_record(NULL::countries,$1)",
            [country]
          )

    for region <- fixture["regions"],
        do:
          rows(
            "INSERT INTO regions(id,code,geom,created_at,updated_at) SELECT id,code,geom,created_at,updated_at FROM json_populate_record(NULL::regions,$1)",
            [region]
          )

    for point <- hd(fixture["steps"])["points"],
        do:
          rows("INSERT INTO points SELECT * FROM json_populate_record(NULL::points,$1)", [point])

    %{uid: user["id"], next: Enum.at(fixture["steps"], 1)["points"]}
  end

  @tag a12f3b_case: "A04a"
  test "achievement bulk check publishes native checks and one unlock", %{uid: uid, next: points} do
    Ownership.put!(ScratchRepo, "command:achievements.check", :sidekiq)

    args = %{
      "event_id" => Ecto.UUID.generate(),
      "stale_only" => true,
      "force" => true,
      "notify" => false
    }

    assert BulkCheck.run(ScratchRepo, @oban, args, now: @now) == :ok
    assert [[payload, at]] = rows("SELECT args,scheduled_at FROM oban.oban_jobs")

    assert payload == %{
             "user_id" => uid,
             "notify" => false,
             "oldest_timestamp" => nil,
             "event_id" => BulkCheck.child_id(args["event_id"], uid)
           }

    assert NaiveDateTime.compare(at, DateTime.to_naive(@now)) == :eq
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    assert BulkCheck.run(ScratchRepo, @oban, args, now: @now) == :ok
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]
    assert CheckWorker.perform(%Oban.Job{args: payload}) == :ok
    assert rows("SELECT count(*) FROM achievement_unlock_events") == [[0]]

    assert BulkCheck.run(ScratchRepo, @oban, Map.put(args, "event_id", Ecto.UUID.generate()),
             now: @now
           ) == :ok

    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]

    for point <- points,
        do:
          rows("INSERT INTO points SELECT * FROM json_populate_record(NULL::points,$1)", [point])

    notify = %{
      args
      | "event_id" => Ecto.UUID.generate(),
        "stale_only" => false,
        "notify" => true,
        "force" => false
    }

    assert BulkCheck.run(ScratchRepo, @oban, notify, now: @now) == :ok
    [[payload]] = rows("SELECT args FROM oban.oban_jobs ORDER BY id DESC LIMIT 1")
    assert CheckWorker.perform(%Oban.Job{args: payload}) == :ok
    assert CheckWorker.perform(%Oban.Job{args: payload}) == :ok
    assert rows("SELECT kind,key FROM achievement_unlock_events") == [["geography", "DE-ST"]]
    assert [[title]] = rows("SELECT title FROM notifications")
    assert title =~ "Saxony-Anhalt"
    assert rows("SELECT count(*) FROM achievement_progresses WHERE user_id=$1", [uid]) == [[1]]
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  @tag a12f3b_case: "A04b"
  test "achievement check failure does not celebrate an uncommitted unlock", %{
    uid: uid,
    next: points
  } do
    args = %{"user_id" => uid, "notify" => true, "oldest_timestamp" => nil}
    assert CheckWorker.perform(%Oban.Job{args: args}) == :ok

    for point <- points,
        do:
          rows("INSERT INTO points SELECT * FROM json_populate_record(NULL::points,$1)", [point])

    before = snapshot(uid)

    rows(
      "CREATE FUNCTION a12f3b_notice_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'native achievement notification failure'; END $$"
    )

    rows(
      "CREATE TRIGGER a12f3b_notice_failure BEFORE INSERT ON notifications FOR EACH ROW EXECUTE FUNCTION a12f3b_notice_failure()"
    )

    assert_raise Postgrex.Error, ~r/native achievement notification failure/, fn ->
      CheckWorker.perform(%Oban.Job{args: args})
    end

    assert snapshot(uid) == before
    rows("DROP TRIGGER a12f3b_notice_failure ON notifications")
    rows("DROP FUNCTION a12f3b_notice_failure()")
    assert CheckWorker.perform(%Oban.Job{args: args}) == :ok
    assert CheckWorker.perform(%Oban.Job{args: args}) == :ok
    assert rows("SELECT kind,key FROM achievement_unlock_events") == [["geography", "DE-ST"]]
    assert rows("SELECT count(*) FROM notifications") == [[1]]
  end

  defp snapshot(uid) do
    for table <-
          ~w(achievement_progresses achievement_unlock_events user_achievements notifications),
        do: rows("SELECT to_jsonb(t) FROM #{table} t WHERE user_id=$1 ORDER BY id", [uid])
  end
end
