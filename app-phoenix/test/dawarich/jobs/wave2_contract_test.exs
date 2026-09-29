defmodule Dawarich.Jobs.Wave2ContractTest do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.{Housekeeping, Registry}
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
      ~r/^\s*'([a-z0-9_.]+)' => \{/m
      |> Regex.scan(RailsTree.read("app/services/job_commands.rb"), capture: :all_but_first)
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

    rails = MapSet.new(commands ++ mails)

    phoenix =
      for %{kind: :command, key: "command:" <> type} <- Registry.entries(),
          into: MapSet.new(),
          do: type

    assert MapSet.subset?(MapSet.new(@wave2_types), rails)
    assert rails == phoenix
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

  test "every worker's queue is in the runtime queue literal, and the pool is Σ + 3" do
    config = Config.Reader.read!(@runtime, env: :prod)[:dawarich]
    queues = config[Oban][:queues]

    for %{worker: worker} <- Registry.entries() do
      assert Keyword.has_key?(queues, worker.__opts__()[:queue]), inspect(worker)
    end

    assert config[Dawarich.Repo][:pool_size] == Enum.sum(Keyword.values(queues)) + 3
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
