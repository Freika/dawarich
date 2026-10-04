defmodule Dawarich.Digests.WorkersTest do
  use Dawarich.JobsCase

  alias Dawarich.DigestFixtures, as: F
  alias Dawarich.Digests.{Calculation, MonthlyWorker, YearlyWorker}

  test "monthly and yearly workers use Jobs.repo and execute their decoded period through Generation" do
    assert Dawarich.Jobs.repo() == ScratchRepo

    for {kind, worker} <- [{"monthly", MonthlyWorker}, {"yearly", YearlyWorker}] do
      for profile <- ~w(new no_data missing_user deleted_user) do
        reset!(ScratchRepo)
        kase = F.job_case!("#{profile}_#{kind}_en")
        F.load!(ScratchRepo, kase)
        args = F.job_args(kase)
        payload = Map.delete(args, "event_id")
        assert worker.args_from_command(1, payload) == {:ok, payload}
        changeset = worker.new(args)
        assert Ecto.Changeset.get_field(changeset, :queue) == "projections"
        assert Ecto.Changeset.get_field(changeset, :max_attempts) == 3
        assert worker.perform(%Oban.Job{args: args}, F.job_options(kase)) == :ok
        expected = if profile in ~w(missing_user deleted_user), do: 0, else: 1

        assert [[^expected]] =
                 rows(
                   "SELECT count(*) FROM phoenix.rails_commands WHERE kind LIKE 'digests.email_%'"
                 )

        if profile == "new" do
          [digest] = F.digests(ScratchRepo, 14101)
          [recorded] = kase["expected"]["rows"]
          assert digest == Map.put(recorded, "id", digest["id"])

          assert [[email_kind]] =
                   rows(
                     "SELECT kind FROM phoenix.rails_commands WHERE kind LIKE 'digests.email_%'"
                   )

          assert email_kind ==
                   if(kind == "monthly", do: "digests.email_month", else: "digests.email_year")
        end
      end

      for origin <- [:stats, :digest] do
        reset!(ScratchRepo)
        kase = F.job_case!("new_#{kind}_en")
        F.load!(ScratchRepo, kase)
        args = F.job_args(kase)
        error = %Postgrex.Error{message: "synthetic database failure"}

        extra =
          if origin == :stats,
            do: [stats_opts: [hexagons: fn _, _, _, _ -> raise error end]],
            else: [before_store: fn _ -> raise error end]

        assert worker.perform(%Oban.Job{args: args}, Keyword.merge(F.job_options(kase), extra)) ==
                 :ok

        expected = if origin == :stats, do: 1, else: 0

        assert [[^expected]] =
                 rows(
                   "SELECT count(*) FROM phoenix.rails_commands WHERE kind LIKE 'digests.email_%'"
                 )

        assert [[1]] = rows("SELECT count(*) FROM phoenix.processed_commands")

        assert [[count]] =
                 rows("SELECT count(*) FROM notifications WHERE user_id=14101 AND kind=2")

        assert count >= 1
      end

      assert {:error, :control_fault} =
               ScratchRepo.transaction(fn ->
                 assert {:error, %Postgrex.Error{}} =
                          ScratchRepo.query("SELECT 1/0", [], log: false)

                 kase = F.job_case!("new_#{kind}_en")

                 assert {:error, %Postgrex.Error{}} =
                          worker.perform(%Oban.Job{args: F.job_args(kase)}, F.job_options(kase))

                 ScratchRepo.rollback(:control_fault)
               end)
    end
  end

  test "real monthly and yearly calculator failures retain originating frames in the bounded notification" do
    for {kind, worker} <- [{"monthly", MonthlyWorker}, {"yearly", YearlyWorker}] do
      reset!(ScratchRepo)
      kase = F.job_case!("new_#{kind}_en")
      F.load!(ScratchRepo, kase)
      args = F.job_args(kase)
      opts = Keyword.put(F.job_options(kase), :uuid, "invalid-uuid")

      result =
        if kind == "monthly",
          do: Calculation.monthly(ScratchRepo, 14101, 2025, 3, opts),
          else: Calculation.yearly(ScratchRepo, 14101, 2025, opts)

      assert {:error, %ArgumentError{}} = result
      assert worker.perform(%Oban.Job{args: args}, opts) == :ok
      assert [[content]] = rows("SELECT content FROM notifications WHERE user_id=14101")
      assert content =~ "invalid-uuid"
      assert content =~ "Dawarich.Digests.Store.save!"
      assert content =~ "Dawarich.Digests.Calculation"

      stack =
        content
        |> String.split("stacktrace: ", parts: 2)
        |> List.last()
        |> String.split("\n", trim: true)

      assert length(stack) <= 20
      assert [[1]] = rows("SELECT count(*) FROM phoenix.processed_commands")
      assert [[1]] = rows("SELECT count(*) FROM phoenix.notification_events")

      assert [[0]] =
               rows(
                 "SELECT count(*) FROM phoenix.rails_commands WHERE kind LIKE 'digests.email_%'"
               )
    end
  end
end
