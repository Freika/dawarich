defmodule Dawarich.Lite.ArchivalWarningWorkerTest do
  use Dawarich.JobsCase

  alias Dawarich.I18n
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Lite.{ArchivalWarnings, ArchivalWarningWorker}

  @oban Dawarich.ArchivalWarningTestOban
  @fixture Path.expand("../../fixtures/wave2/archival_cutoffs.json", __DIR__)
  @mail_key "command:mail.user.archival_approaching"
  @tz "Europe/Berlin"
  @now ~U[2026-03-29 01:30:00Z]
  @mark "2026-03-29T03:30:00+02:00"
  @c11 1_745_890_200
  @c11_5 1_744_594_200
  @c12 1_743_215_400
  @scope "jobs.lite.archival_warning_job."

  setup do
    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "false")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    start_oban(@oban)
    :ok = Ownership.put!(ScratchRepo, ArchivalWarningWorker.key(), :oban)
    :ok = Ownership.put!(ScratchRepo, @mail_key, :oban)
    :ok
  end

  defp user!(attrs) do
    [[id]] =
      rows(
        "INSERT INTO users (email, plan, settings, deleted_at, active_until, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, now(), now()) RETURNING id",
        [
          "lite-#{System.unique_integer([:positive])}@example.test",
          Map.get(attrs, :plan, 0),
          Map.get(attrs, :settings, %{"locale" => "de"}),
          Map.get(attrs, :deleted_at),
          Map.get(attrs, :active_until)
        ]
      )

    if oldest = Map.get(attrs, :oldest) do
      rows(
        "INSERT INTO points (user_id, timestamp, created_at, updated_at) VALUES ($1, $2, now(), now()), ($1, $2 + 86400, now(), now())",
        [id, oldest]
      )
    end

    id
  end

  defp run(now \\ @now), do: ArchivalWarningWorker.run(ScratchRepo, @oban, now, @tz)

  defp warnings(user_id) do
    [[warnings]] =
      rows("SELECT settings->'archival_warnings' FROM users WHERE id = $1", [user_id])

    warnings
  end

  defp notifications,
    do: rows("SELECT user_id, kind, title, content FROM notifications ORDER BY id")

  defp jobs,
    do: rows("SELECT worker, queue, args FROM oban.oban_jobs ORDER BY id")

  defp text(locale, key) do
    {:ok, text} = I18n.t(locale, @scope <> key)
    text
  end

  defp parse_instant(instant) do
    {:ok, time, 0} =
      instant
      |> String.replace(" UTC", "Z")
      |> String.replace(" ", "T")
      |> DateTime.from_iso8601()

    time
  end

  test "cutoffs equal Rails' durations for every fixture instant and zone" do
    fixture = @fixture |> File.read!() |> Jason.decode!()
    assert Map.keys(fixture) |> Enum.sort() == ["Etc/UTC", "Europe/Berlin"]

    for {tz, instants} <- fixture, {instant, expected} <- instants do
      {:ok, {c11, c11_5, c12, _marked_at}} =
        ScratchRepo.transaction(fn ->
          ArchivalWarnings.cutoffs(ScratchRepo, tz, parse_instant(instant))
        end)

      assert [c11, c11_5, c12] == expected, "#{tz} #{instant}"
    end

    assert {:ok, {_, _, _, "2026-03-29T01:30:00Z"}} =
             ScratchRepo.transaction(fn ->
               ArchivalWarnings.cutoffs(ScratchRepo, "Etc/UTC", @now)
             end)

    assert {:ok, {_, _, _, @mark}} =
             ScratchRepo.transaction(fn -> ArchivalWarnings.cutoffs(ScratchRepo, @tz, @now) end)
  end

  test "an ActiveSupport TIME_ZONE name resolves to its IANA zone before the zone lookup" do
    user_id = user!(%{oldest: @c11_5 - 100})

    assert ArchivalWarningWorker.run(ScratchRepo, @oban, @now, "Berlin") == :ok

    assert warnings(user_id) == %{"11mo" => @mark, "11_5mo" => @mark}
    assert [[_, _, %{"epoch" => @mark}]] = jobs()
  end

  test "only the most severe unsent crossed threshold acts; every crossed key gets the same mark" do
    all = user!(%{oldest: @c12 - 100})
    partly = user!(%{oldest: @c11_5 - 100, settings: %{"archival_warnings" => %{"11mo" => "x"}}})

    assert run() == :ok

    assert warnings(all) == %{"11mo" => @mark, "11_5mo" => @mark, "12mo" => @mark}
    assert warnings(partly) == %{"11mo" => "x", "11_5mo" => @mark}

    assert notifications() == [
             [
               all,
               1,
               text("de", "data_has_been_archived"),
               text("de", "month_of_location_data_has_been_archived_your_archived")
             ]
           ]

    assert [["Dawarich.Mail.ArchivalApproachingWorker", "mailers", %{"user_id" => ^partly}]] =
             jobs()
  end

  test "11mo and 12mo create warning notifications in the user's locale, each with an event" do
    approaching = user!(%{oldest: @c11 - 100, settings: %{"locale" => "fr"}})
    archived = user!(%{oldest: @c12 - 100, settings: %{"locale" => "pl"}})

    assert run() == :ok

    assert notifications() == [
             [
               approaching,
               1,
               text("fr", "your_oldest_data_will_archive_in_30_days"),
               text("fr", "your_oldest_month_of_location_data_will_be_archived_soon")
             ],
             [
               archived,
               1,
               text("pl", "data_has_been_archived"),
               text("pl", "month_of_location_data_has_been_archived_your_archived")
             ]
           ]

    assert rows(
             "SELECT n.user_id FROM phoenix.notification_events e JOIN notifications n ON n.id = e.notification_id ORDER BY e.id"
           ) == [[approaching], [archived]]

    assert jobs() == []
  end

  test "11_5mo inserts one ArchivalApproachingWorker job whose epoch equals the mark" do
    user_id = user!(%{oldest: @c11_5 - 100, settings: %{"locale" => "es"}})

    assert run() == :ok

    assert warnings(user_id) == %{"11mo" => @mark, "11_5mo" => @mark}
    assert notifications() == []

    assert [["Dawarich.Mail.ArchivalApproachingWorker", "mailers", args]] = jobs()
    assert %{"user_id" => ^user_id, "locale" => "es", "epoch" => @mark} = args
    assert {:ok, _} = Ecto.UUID.cast(args["event_id"])
    assert map_size(args) == 4
  end

  test "11_5mo after joint mail handback cancels without marks jobs or notifications" do
    :ok = Ownership.put!(ScratchRepo, @mail_key, :sidekiq)
    user_id = user!(%{oldest: @c11_5 - 100})

    assert run() == {:cancel, :not_owner}
    assert warnings(user_id) == nil
    assert jobs() == []
    assert notifications() == []
  end

  test "a user whose most severe key is already marked is untouched" do
    settings = %{"locale" => "de", "archival_warnings" => %{"12mo" => ""}}
    user_id = user!(%{oldest: @c12 - 100, settings: settings})

    assert run() == :ok

    assert warnings(user_id) == %{"12mo" => ""}
    assert notifications() == []
    assert jobs() == []
  end

  test "inherited family access, self-hosted and soft-deleted users are skipped" do
    owner = user!(%{plan: 2, active_until: ~N[2027-01-01 00:00:00]})
    by_owner = user!(%{oldest: @c12 - 100})
    by_date = user!(%{oldest: @c12 - 100})
    deleted = user!(%{oldest: @c12 - 100, deleted_at: ~N[2026-01-01 00:00:00]})
    eligible = user!(%{oldest: @c12 - 100})

    for {member, access_until} <- [{by_owner, nil}, {by_date, ~N[2099-01-01 00:00:00]}] do
      [[family_id]] =
        rows(
          "INSERT INTO families (name, creator_id, access_until, created_at, updated_at) VALUES ('F', $1, $2, now(), now()) RETURNING id",
          [owner, access_until]
        )

      rows(
        "INSERT INTO family_memberships (family_id, user_id, role, created_at, updated_at) VALUES ($1, $2, 1, now(), now())",
        [family_id, member]
      )
    end

    System.put_env("SELF_HOSTED", "true")
    assert run() == :ok
    assert warnings(eligible) == nil

    System.put_env("SELF_HOSTED", "false")
    assert run() == :ok

    assert for(id <- [by_owner, by_date, deleted], do: warnings(id)) == [nil, nil, nil]
    assert [[^eligible | _]] = notifications()
  end

  test "returns {:cancel, :not_owner} at the first user once the cron key is not oban" do
    :ok = Ownership.put!(ScratchRepo, ArchivalWarningWorker.key(), :sidekiq)
    first = user!(%{oldest: @c12 - 100})
    second = user!(%{oldest: @c11 - 100})

    assert run() == {:cancel, :not_owner}

    assert warnings(first) == nil
    assert warnings(second) == nil
    assert notifications() == []
  end

  test "after a plan-change reset the same threshold acts again with a new epoch" do
    user_id = user!(%{oldest: @c11_5 - 100})

    assert run() == :ok
    assert run(DateTime.add(@now, 3600)) == :ok
    assert [[_, _, %{"epoch" => @mark}]] = jobs()

    rows(
      "UPDATE users SET settings = COALESCE(settings, '{}'::jsonb) - 'archival_warnings' - 'lite_since' WHERE id = $1",
      [user_id]
    )

    assert run(DateTime.add(@now, 86_400)) == :ok

    assert [[_, _, %{"epoch" => @mark}], [_, _, %{"epoch" => second}]] = jobs()
    assert second == "2026-03-30T03:30:00+02:00"
    assert warnings(user_id)["11_5mo"] == second
  end

  test "the keyset scan visits every Lite user once in id order across batches" do
    users =
      rows("""
      INSERT INTO users (email, plan, settings, created_at, updated_at)
      SELECT 'scan-' || g || '@example.test', CASE WHEN g % 6 = 0 THEN 1 ELSE 0 END, '{}', now(), now()
      FROM generate_series(1, 300) g
      RETURNING id, plan
      """)

    rows(
      "INSERT INTO points (user_id, timestamp, created_at, updated_at) SELECT id, $1, now(), now() FROM users",
      [@c11 - 100]
    )

    lite = for [id, 0] <- users, do: id
    assert length(lite) == 250

    assert run() == :ok

    assert rows("SELECT user_id FROM notifications ORDER BY id") ==
             Enum.map(Enum.sort(lite), &[&1])
  end
end
