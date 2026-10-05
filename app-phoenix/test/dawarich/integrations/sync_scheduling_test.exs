defmodule Dawarich.Integrations.SyncSchedulingTest do
  use Dawarich.JobsCase

  alias Dawarich.Integrations.{SyncScheduling, TeslaMateSchedulingWorker, TrekSchedulingWorker}
  alias Dawarich.Jobs.{Ownership, Processed}

  @slot 1_759_050_000
  @now ~U[2026-10-04 12:00:00Z]
  @oban __MODULE__.Oban

  setup do
    start_oban(@oban)
    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "false")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    :ok
  end

  defp user!(settings \\ %{}, status \\ 1, plan \\ 0) do
    [[id]] =
      rows(
        "INSERT INTO users (email, settings, status, plan, created_at, updated_at) " <>
          "VALUES ($1, $2, $3, $4, now(), now()) RETURNING id",
        [
          "integrations-#{System.unique_integer([:positive])}@example.test",
          settings,
          status,
          plan
        ]
      )

    id
  end

  defp source!(user, status \\ 0, provider \\ "trek") do
    [[id]] =
      rows(
        "INSERT INTO trip_sources (user_id, status, provider, base_url, api_key, created_at, updated_at) " <>
          "VALUES ($1, $2, $3, $4, 'synthetic', now(), now()) RETURNING id",
        [user, status, provider, "https://trek-#{System.unique_integer([:positive])}.example"]
      )

    id
  end

  defp own!(kind), do: Ownership.put!(ScratchRepo, SyncScheduling.key(kind), :oban)

  defp run(kind, opts \\ []),
    do: SyncScheduling.run(ScratchRepo, @oban, kind, @slot, [now: @now] ++ opts)

  defp commands, do: rows("SELECT kind, payload FROM phoenix.rails_commands ORDER BY id")

  defp ids(kind),
    do:
      commands()
      |> Enum.filter(fn [name, _] -> name == "integrations.#{kind}_sync" end)
      |> Enum.map(fn [_, p] -> p["source_id"] || p["user_id"] end)

  test "Trek and TeslaMate schedulers publish one native child or one retained reverse intent per slot" do
    user = user!(%{"teslamate_url" => "https://synthetic.example"}, 0, 1)
    source = source!(user)
    for kind <- [:teslamate, :trek], do: own!(kind)

    for owner <- [:oban, :sidekiq] do
      rows("DELETE FROM oban.oban_jobs")
      rows("DELETE FROM phoenix.rails_commands")
      rows("DELETE FROM phoenix.processed_commands")

      for kind <- [:teslamate, :trek],
          do: Ownership.put!(ScratchRepo, "command:imports.#{kind}_sync", owner)

      for kind <- [:teslamate, :trek], do: assert(run(kind) == :ok)
      jobs = rows("SELECT worker, args FROM oban.oban_jobs ORDER BY worker")
      intents = commands()

      if owner == :oban do
        assert jobs == [
                 [
                   "Dawarich.Imports.Teslamate.SyncWorker",
                   %{
                     "user_id" => user,
                     "event_id" => SyncScheduling.event_id(:teslamate, @slot, user)
                   }
                 ],
                 [
                   "Dawarich.Imports.Trek.SyncWorker",
                   %{
                     "source_id" => source,
                     "after_id" => nil,
                     "event_id" => SyncScheduling.event_id(:trek, @slot, source)
                   }
                 ]
               ]

        assert intents == []

        for [worker, args] <- jobs do
          module = String.to_existing_atom("Elixir." <> worker)
          payload = Map.delete(args, "event_id")
          assert module.args_from_command(1, payload) == {:ok, payload}
        end
      else
        assert jobs == []

        assert intents == [
                 [
                   "integrations.teslamate_sync",
                   %{
                     "user_id" => user,
                     "event_id" => SyncScheduling.event_id(:teslamate, @slot, user)
                   }
                 ],
                 [
                   "integrations.trek_sync",
                   %{
                     "user_id" => user,
                     "source_id" => source,
                     "event_id" => SyncScheduling.event_id(:trek, @slot, source)
                   }
                 ]
               ]
      end

      for kind <- [:teslamate, :trek] do
        Ownership.put!(
          ScratchRepo,
          "command:imports.#{kind}_sync",
          if(owner == :oban, do: :sidekiq, else: :oban)
        )

        assert run(kind) == :ok
      end

      assert rows("SELECT worker, args FROM oban.oban_jobs ORDER BY worker") == jobs
      assert commands() == intents
      assert rows("SELECT count(*) FROM phoenix.processed_commands") == [[2]]
    end

    rows("DELETE FROM oban.oban_jobs")
    rows("DELETE FROM phoenix.rails_commands")

    for {kind, id} <- [teslamate: user, trek: source] do
      receipt = SyncScheduling.receipt_id(kind, @slot + 60, id)

      assert_raise Postgrex.Error, fn ->
        SyncScheduling.run(ScratchRepo, @oban, kind, @slot + 60,
          now: @now,
          hook: fn _ -> ScratchRepo.query!("SELECT 1 / 0", [], log: false) end
        )
      end

      refute Processed.done?(ScratchRepo, receipt)
      assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
      assert commands() == []
    end
  end

  test "TeslaMate preserves URL-only selection and Trek preserves active entitlement selection" do
    own!(:teslamate)
    own!(:trek)
    inactive = user!(%{"teslamate_url" => "https://teslamate.example"}, 0)
    whitespace = user!(%{"teslamate_url" => " "}, 3)
    user!(%{"teslamate_url" => ""})
    user!(%{"teslamate_url" => nil})
    deleted = user!(%{"teslamate_url" => "https://a"})
    rows("UPDATE users SET deleted_at = now() WHERE id = $1", [deleted])

    extra =
      rows(
        "INSERT INTO users (email, settings, status, created_at, updated_at) " <>
          "SELECT 'teslamate-batch-' || g || '@example.test', $1, 0, now(), now() FROM generate_series(1,1001) g RETURNING id",
        [%{"teslamate_url" => "https://teslamate.example"}]
      )
      |> List.flatten()

    paid = user!(%{}, 0, 1)
    active = source!(paid)
    source!(paid, 1)
    source!(paid, 0, "other")
    source!(user!())
    assert TeslaMateSchedulingWorker.key() == SyncScheduling.key(:teslamate)
    assert TrekSchedulingWorker.key() == SyncScheduling.key(:trek)
    assert run(:teslamate) == :ok
    assert ids(:teslamate) == [inactive, whitespace] ++ extra
    assert run(:trek) == :ok
    assert ids(:trek) == [active]
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
  end

  test "Trek accepts inherited full access and excludes disabled or wrong-provider sources" do
    own!(:trek)
    owner = user!(%{}, 1, 2)
    member = user!()

    [[family]] =
      rows(
        "INSERT INTO families (name, creator_id, access_until, created_at, updated_at) " <>
          "VALUES ('Synthetic family', $1, $2, now(), now()) RETURNING id",
        [owner, DateTime.add(@now, 86400) |> DateTime.to_naive()]
      )

    rows(
      "INSERT INTO family_memberships (family_id, user_id, created_at, updated_at) VALUES ($1, $2, now(), now())",
      [family, member]
    )

    inherited = source!(member)
    denied = source!(user!())
    source!(member, 1)
    source!(member, 0, "other")
    assert run(:trek) == :ok
    assert ids(:trek) == [inherited]
    System.put_env("SELF_HOSTED", "true")
    assert SyncScheduling.run(ScratchRepo, @oban, :trek, @slot + 60, now: @now) == :ok
    assert ids(:trek) == [inherited, inherited, denied]
  end

  test "scheduler replay and hand-back publish each slot child once without account data" do
    user = user!(%{"teslamate_url" => "https://a", "teslamate_api_key" => "synthetic"}, 0, 1)
    source = source!(user)
    assert run(:teslamate) == {:cancel, :not_owner}
    for kind <- [:teslamate, :trek], do: own!(kind)
    for kind <- [:teslamate, :trek], do: assert(run(kind) == :ok)

    expected = [
      [
        "integrations.teslamate_sync",
        %{"user_id" => user, "event_id" => SyncScheduling.event_id(:teslamate, @slot, user)}
      ],
      [
        "integrations.trek_sync",
        %{
          "source_id" => source,
          "user_id" => user,
          "event_id" => SyncScheduling.event_id(:trek, @slot, source)
        }
      ]
    ]

    assert commands() == expected
    for kind <- [:teslamate, :trek], do: assert(run(kind) == :ok)
    assert commands() == expected
    Ownership.put!(ScratchRepo, SyncScheduling.key(:trek), :sidekiq)
    assert SyncScheduling.run(ScratchRepo, @oban, :trek, @slot + 60) == {:cancel, :not_owner}
    assert commands() == expected
    rows("DELETE FROM phoenix.rails_commands")
    receipt = SyncScheduling.receipt_id(:teslamate, @slot + 60, user)
    Processed.mark!(ScratchRepo, receipt, "Rails scheduler")
    assert SyncScheduling.run(ScratchRepo, @oban, :teslamate, @slot + 60) == :ok
    assert commands() == []
    failed_receipt = SyncScheduling.receipt_id(:teslamate, @slot + 120, user)

    assert_raise Postgrex.Error, fn ->
      SyncScheduling.run(ScratchRepo, @oban, :teslamate, @slot + 120,
        hook: fn _ -> ScratchRepo.query!("SELECT 1 / 0", [], log: false) end
      )
    end

    refute Processed.done?(ScratchRepo, failed_receipt)
    assert commands() == []
    assert SyncScheduling.run(ScratchRepo, @oban, :teslamate, @slot + 120) == :ok
    assert length(commands()) == 1
  end

  test "scheduler retries retain characterized Sidekiq attempt limits and backoff" do
    for worker <- [
          TeslaMateSchedulingWorker,
          TrekSchedulingWorker,
          Dawarich.AirTrail.SyncSchedulingWorker
        ] do
      assert worker.__opts__()[:max_attempts] == 26
      assert worker.__opts__()[:queue] == :imports
      assert worker.backoff(%Oban.Job{attempt: 1}) in 15..24
      assert worker.backoff(%Oban.Job{attempt: 10}) in 6576..6675
    end
  end
end
