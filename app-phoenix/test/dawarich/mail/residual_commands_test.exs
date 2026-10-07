defmodule Dawarich.Mail.ResidualCommandsTest do
  use Dawarich.JobsCase
  use Dawarich.IngestCase

  alias Dawarich.DigestFixtures, as: F
  alias Dawarich.Digests.Generation
  alias Dawarich.Jobs.{Dispatch, Ownership, Registry}
  alias Dawarich.Mail.{ResidualCommands, ResidualEntries}
  alias Dawarich.Test.ApiGolden

  test "residual mail owner selection keeps Rails OFF and settles exactly one native command ON" do
    start_oban(:residual_commands)
    entries = ResidualEntries.entries()

    assert Enum.map(entries, & &1.key) ==
             ~w(command:mail.family_location_request command:mail.digest.monthly command:mail.digest.yearly)

    assert Enum.all?(entries, &(&1.claimable == false))
    assert Registry.claimable() == []

    for period <- ~w(monthly yearly),
        owner <- [:sidekiq, :oban],
        preference <- ["invalid", " DE "] do
      reset!(ScratchRepo)
      kase = F.job_case!("new_#{period}_en")
      F.load!(ScratchRepo, kase)

      rows(
        "UPDATE public.users SET settings=jsonb_set(settings,'{locale}',$1::jsonb) WHERE id=14101",
        [preference]
      )

      Ownership.put!(ScratchRepo, "command:mail.digest.#{period}", owner)
      args = F.job_args(kase)
      assert Generation.run(ScratchRepo, period, args, F.job_options(kase)) == :ok
      assert Generation.run(ScratchRepo, period, args, F.job_options(kase)) == :ok

      assert [[1]] =
               rows(
                 "SELECT count(*) FROM phoenix.processed_commands WHERE handler NOT LIKE 'digests.generate_%'"
               )

      if owner == :sidekiq do
        kind = if period == "monthly", do: "digests.email_month", else: "digests.email_year"

        assert [[^kind, payload]] =
                 rows(
                   "SELECT kind,payload FROM phoenix.rails_commands WHERE kind LIKE 'digests.email_%'"
                 )

        assert payload == Map.delete(args, "event_id")
        assert [] == rows("SELECT event_id FROM public.job_outbox")
      else
        assert [] ==
                 rows("SELECT kind FROM phoenix.rails_commands WHERE kind LIKE 'digests.email_%'")

        type = "mail.digest." <> period

        assert [[^type, 1, payload]] =
                 rows("SELECT command_type,command_version,payload FROM public.job_outbox")

        expected =
          Map.delete(args, "event_id")
          |> Map.put("locale", if(preference == "invalid", do: "en", else: "de"))

        assert payload == expected
        assert Dispatch.run(repo: ScratchRepo, oban: :residual_commands) == %{dispatched: 1}
        assert Dispatch.run(repo: ScratchRepo, oban: :residual_commands) == %{}
        assert [[1]] = rows("SELECT count(*) FROM oban.oban_jobs")
        assert [[job_args]] = rows("SELECT args FROM oban.oban_jobs")
        assert Map.delete(job_args, "event_id") == expected
      end
    end

    for period <- ~w(monthly yearly) do
      reset!(ScratchRepo)
      kase = F.job_case!("new_#{period}_en")
      F.load!(ScratchRepo, kase)
      Ownership.put!(ScratchRepo, "command:mail.digest.#{period}", :oban)
      fault = %RuntimeError{message: "synthetic residual terminal fault"}

      assert Generation.run(
               ScratchRepo,
               period,
               F.job_args(kase),
               Keyword.put(F.job_options(kase), :after_terminal, fn -> raise fault end)
             ) == {:error, fault}

      assert [[0]] =
               rows(
                 "SELECT count(*) FROM phoenix.processed_commands WHERE handler NOT LIKE 'digests.generate_%'"
               )

      assert [[2]] =
               rows(
                 "SELECT count(*) FROM phoenix.processed_commands WHERE handler LIKE 'digests.generate_%'"
               )

      assert [] == rows("SELECT event_id FROM public.job_outbox")
      assert [] == rows("SELECT id FROM phoenix.rails_commands WHERE kind LIKE 'digests.email_%'")
    end

    for owner <- [:sidekiq, :oban] do
      reset!(ScratchRepo)
      payload = %{"request_id" => 460_500, "user_id" => 460_300}
      Ownership.put!(ScratchRepo, "command:mail.family_location_request", owner)
      assert ResidualCommands.location(ScratchRepo, payload) == :ok

      if owner == :sidekiq do
        assert [["family_location_request_mail", ^payload]] =
                 rows("SELECT kind,payload FROM phoenix.rails_commands")

        assert [] == rows("SELECT event_id FROM public.job_outbox")
      else
        assert [] == rows("SELECT kind FROM phoenix.rails_commands")

        assert [["mail.family_location_request", ^payload]] =
                 rows("SELECT command_type,payload FROM public.job_outbox")

        assert Dispatch.run(repo: ScratchRepo, oban: :residual_commands) == %{dispatched: 1}
        assert [[1]] = rows("SELECT count(*) FROM oban.oban_jobs")
      end
    end

    actual_family_producer()
  end

  defp actual_family_producer do
    Repo.query!(File.read!("priv/repo/sql/20260928120000_wave2.sql"), [], query_type: :text)
    golden = "test/fixtures/api_family/writes.json" |> File.read!() |> Jason.decode!()
    kase = Enum.find(golden["cases"], &(&1["name"] == "create_request"))

    for owner <- [:sidekiq, :oban] do
      Repo.query!(
        "TRUNCATE public.users,public.families,public.job_outbox,phoenix.rails_commands,phoenix.notification_events CASCADE",
        [],
        log: false
      )

      setup = golden["setups"][kase["setup"]]
      for [table, records] <- setup, row <- records, do: ApiGolden.insert!(table, row)
      Ownership.put!(Repo, "command:mail.family_location_request", owner)

      [[requester]] =
        Repo.query!("SELECT creator_id FROM public.families LIMIT 1", [], log: false).rows

      [[target]] =
        Repo.query!(
          "SELECT user_id FROM public.family_memberships WHERE user_id<>$1 LIMIT 1",
          [requester],
          log: false
        ).rows

      {:ok, now, _} = DateTime.from_iso8601(golden["now"])

      assert {:ok, {:ok, 201, _}} =
               Repo.transaction(fn ->
                 Dawarich.Families.Requests.create(
                   %{id: requester, timezone: "UTC"},
                   %{"target_user_id" => target},
                   now
                 )
               end)

      assert [[1]] = Repo.query!("SELECT count(*) FROM public.notifications", [], log: false).rows

      if owner == :oban do
        assert [["mail.family_location_request"]] =
                 Repo.query!("SELECT command_type FROM public.job_outbox", [], log: false).rows

        assert [] == Repo.query!("SELECT id FROM phoenix.rails_commands", [], log: false).rows
      else
        assert [["family_location_request_mail"]] =
                 Repo.query!("SELECT kind FROM phoenix.rails_commands", [], log: false).rows

        assert [] == Repo.query!("SELECT event_id FROM public.job_outbox", [], log: false).rows
      end
    end
  end
end
