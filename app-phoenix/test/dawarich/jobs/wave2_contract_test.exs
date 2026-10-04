defmodule Dawarich.Jobs.Wave2ContractTest do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.{Housekeeping, Ownership, Registry}
  alias Dawarich.Lite.ArchivalWarningWorker
  alias Dawarich.RailsTree

  @payloads Path.expand("../../fixtures/wave2/payloads.json", __DIR__)
  @runtime Path.expand("../../../config/runtime.exs", __DIR__)

  @wave2_types ~w(
    exports.points
    mail.family_invitation
    mail.family_lapse
    mail.user.welcome
    mail.user.archival_approaching
    mail.user.oauth_account_link
    mail.user.account_destroy_confirmation
  )

  test "Rails COMMANDS and the registry name the same command types" do
    commands =
      ~r/'([a-z0-9_.]+)' => \{/
      |> Regex.scan(
        RailsTree.read("app/services/job_commands.rb") <>
          RailsTree.read("app/services/imports/integration_commands.rb") <>
          RailsTree.read("app/services/imports/teslamate_commands.rb") <>
          RailsTree.read("app/services/release_commands.rb") <>
          hd(String.split(RailsTree.read("app/services/stats/commands.rb"), "HANDLERS = {")) <>
          hd(
            String.split(
              RailsTree.read("app/services/posters/creation_command.rb"),
              "HANDLERS = {"
            )
          ),
        capture: :all_but_first
      )
      |> List.flatten()

    [legacy_options] =
      Regex.run(
        ~r/LEGACY_OPTIONS = \{(.*?)\}\.freeze/s,
        RailsTree.read("app/services/user_mail_commands.rb"),
        capture: :all_but_first
      )

    mails =
      ~r/^\s*'([a-z_]+)' =>/m
      |> Regex.scan(legacy_options, capture: :all_but_first)
      |> Enum.map(fn [email_type] -> "mail.user." <> email_type end)

    [_, normal_type] =
      Regex.run(~r/TYPE = '([^']+)'/, RailsTree.read("app/services/imports/process_commands.rb"))

    rails = MapSet.new(commands ++ mails ++ [normal_type])

    phoenix =
      for %{kind: :command, key: "command:" <> type} <- Registry.entries(),
          into: MapSet.new(),
          do: type

    assert MapSet.subset?(MapSet.new(@wave2_types), rails)
    assert phoenix == MapSet.put(rails, "points.anomaly_recalculate")

    assert {:ok, Dawarich.Points.AnomalyFilter.RecalculateWorker} =
             Registry.command("points.anomaly_recalculate")

    assert {:ok, Dawarich.Tracks.RecalculateWorker} = Registry.command("tracks.recalculate")
  end

  test "anomaly compatibility worker uses the canonical track recalculation owner" do
    [[user]] =
      rows(
        "INSERT INTO users(email,created_at,updated_at) VALUES('alias-owner@example.test',now(),now()) RETURNING id"
      )

    [[track]] =
      rows(
        "INSERT INTO tracks(user_id,start_at,end_at,original_path,created_at,updated_at) VALUES($1,now(),now(),ST_GeomFromText('LINESTRING(13.405 52.52,13.406 52.52)',4326),now(),now()) RETURNING id",
        [user]
      )

    args = %{"track_id" => track, "user_id" => user, "job_queue" => nil}
    alias_worker = Dawarich.Points.AnomalyFilter.RecalculateWorker

    Ownership.put!(ScratchRepo, "command:points.anomaly_recalculate", :oban)
    assert :ok = alias_worker.run(ScratchRepo, args)

    assert [[^args]] =
             rows(
               "SELECT payload FROM phoenix.rails_commands WHERE kind='points.anomaly_recalculate'"
             )

    assert [[^track]] = rows("SELECT id FROM tracks WHERE id=$1", [track])

    rows("DELETE FROM phoenix.rails_commands")
    Ownership.put!(ScratchRepo, "command:tracks.recalculate", :oban)
    assert :ok = alias_worker.run(ScratchRepo, args)
    assert [] == rows("SELECT id FROM tracks WHERE id=$1", [track])
    assert [["tracks_changed"]] == rows("SELECT kind FROM phoenix.rails_commands")
  end

  test "every Rails-built payload decodes, and the args hold no personal data" do
    payloads = @payloads |> File.read!() |> Jason.decode!()

    assert Enum.sort(Map.keys(payloads)) == Enum.sort(@wave2_types)

    for {type, payload} <- payloads do
      assert {:ok, worker} = Registry.command(type), type
      assert {:ok, args} = worker.args_from_command(1, payload), type
      assert Enum.all?(Map.values(args), &(is_integer(&1) or is_binary(&1))), type

      json = Jason.encode!(args)
      refute json =~ "@", type
      refute json =~ "http", type
      refute json =~ "token=", type
      refute json =~ "eyJ", type
    end
  end

  test "the Lite cron expression equals config/schedule.yml" do
    [_, expression] =
      Regex.run(
        ~r/^lite_archival_warning_job:\n\s+cron: "([^"]+)"[^\n]*\n\s+class: "Lite::ArchivalWarningJob"/m,
        RailsTree.read("config/schedule.yml")
      )

    assert {expression, ArchivalWarningWorker} in Registry.crontab()
  end

  test "every worker's queue is in the runtime queue literal, and the pool is Σ + 3 + Puma threads" do
    saved = System.get_env("RAILS_MAX_THREADS")
    System.delete_env("RAILS_MAX_THREADS")

    on_exit(fn ->
      if saved,
        do: System.put_env("RAILS_MAX_THREADS", saved),
        else: System.delete_env("RAILS_MAX_THREADS")
    end)

    config = Config.Reader.read!(@runtime, env: :prod)[:dawarich]
    queues = config[Oban][:queues]

    for %{worker: worker} <- Registry.entries() do
      assert Keyword.has_key?(queues, worker.__opts__()[:queue]), inspect(worker)
    end

    assert config[Dawarich.Repo][:pool_size] == Enum.sum(Keyword.values(queues)) + 3 + 5
    assert Keyword.fetch!(queues, :exports) == 1
  end

  test "housekeeping prunes events after a day and claims after 30 days" do
    rows("""
    INSERT INTO phoenix.notification_events (notification_id, created_at)
    VALUES (1, now() - interval '25 hours'), (2, now() - interval '23 hours')
    """)

    rows("""
    INSERT INTO phoenix.delivery_claims (handler, provider_key, event_id, claimed_at, delivered_at)
    VALUES ('h', 'old', gen_random_uuid(), now() - interval '31 days', now() - interval '31 days'),
           ('h', 'kept', gen_random_uuid(), now() - interval '29 days', NULL)
    """)

    rows("""
    INSERT INTO phoenix.export_claims (export_id, event_id, claimed_at)
    VALUES (1, gen_random_uuid(), now() - interval '31 days'),
           (2, gen_random_uuid(), now() - interval '29 days')
    """)

    :ok = Housekeeping.run!(ScratchRepo, DateTime.utc_now())

    assert rows("SELECT notification_id FROM phoenix.notification_events") == [[2]]
    assert rows("SELECT provider_key FROM phoenix.delivery_claims") == [["kept"]]
    assert rows("SELECT export_id FROM phoenix.export_claims") == [[2]]
  end
end
