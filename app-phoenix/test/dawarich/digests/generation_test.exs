defmodule Dawarich.Digests.GenerationTest do
  use Dawarich.JobsCase

  alias Dawarich.DigestFixtures, as: F
  alias Dawarich.Digests.Generation

  test "one stable calculation event settles one terminal effect and nil digest still chains Rails email" do
    for kind <- ~w(monthly yearly),
        profile <- ~w(new existing no_data missing_user deleted_user) do
      reset!(ScratchRepo)
      kase = F.job_case!("#{profile}_#{kind}_en")
      F.load!(ScratchRepo, kase)
      args = F.job_args(kase)
      opts = F.job_options(kase)
      assert Generation.run(ScratchRepo, kind, args, opts) == :ok
      assert Generation.run(ScratchRepo, kind, args, opts) == :ok
      expected = if profile in ~w(missing_user deleted_user), do: 0, else: 1

      assert [[^expected]] =
               rows(
                 "SELECT count(*) FROM phoenix.rails_commands WHERE kind LIKE 'digests.email_%'"
               )

      assert [[1]] =
               rows(
                 "SELECT count(*) FROM phoenix.processed_commands WHERE handler NOT LIKE 'digests.generate_%'"
               )

      if profile == "no_data", do: assert(F.digests(ScratchRepo, 14101) == [])

      if expected == 1 do
        [[payload]] =
          rows("SELECT payload FROM phoenix.rails_commands WHERE kind LIKE 'digests.email_%'")

        assert payload == Map.delete(args, "event_id")

        assert Generation.run(
                 ScratchRepo,
                 kind,
                 Map.put(args, "event_id", Ecto.UUID.generate()),
                 opts
               ) == :ok

        assert [[1]] =
                 rows(
                   "SELECT count(*) FROM phoenix.rails_commands WHERE kind LIKE 'digests.email_%'"
                 )
      end
    end

    reset!(ScratchRepo)
    kase = F.job_case!("no_data_monthly_en")
    F.load!(ScratchRepo, kase)
    args = F.job_args(kase)
    caller = self()

    barrier = fn ->
      send(caller, {:ready, self()})
      receive do: (:claim -> :ok)
    end

    opts = Keyword.put(F.job_options(kase), :before_claim, barrier)
    first = Task.async(fn -> Generation.run(ScratchRepo, "monthly", args, opts) end)
    second = Task.async(fn -> Generation.run(ScratchRepo, "monthly", args, opts) end)
    assert_receive {:ready, first_pid}, 5_000
    assert_receive {:ready, second_pid}, 5_000
    refute first_pid == second_pid
    send(first_pid, :claim)
    send(second_pid, :claim)
    assert Task.await(first) == :ok
    assert Task.await(second) == :ok

    assert [[1]] =
             rows(
               "SELECT count(*) FROM phoenix.processed_commands WHERE handler NOT LIKE 'digests.generate_%'"
             )

    assert [[1]] =
             rows("SELECT count(*) FROM phoenix.rails_commands WHERE kind='digests.email_month'")
  end

  test "terminal write failure leaves no marker and committed calculation can settle on later redelivery" do
    kase = F.job_case!("new_monthly_en")
    F.load!(ScratchRepo, kase)
    args = F.job_args(kase)
    fault = %RuntimeError{message: "terminal fault after reverse insert"}

    fail = fn ->
      assert [[1]] =
               rows(
                 "SELECT count(*) FROM phoenix.processed_commands WHERE handler NOT LIKE 'digests.generate_%'"
               )

      assert [[1]] =
               rows(
                 "SELECT count(*) FROM phoenix.rails_commands WHERE kind='digests.email_month'"
               )

      raise fault
    end

    opts = Keyword.put(F.job_options(kase), :after_terminal, fail)
    assert Generation.run(ScratchRepo, "monthly", args, opts) == {:error, fault}

    assert [[0]] =
             rows(
               "SELECT count(*) FROM phoenix.processed_commands WHERE handler NOT LIKE 'digests.generate_%'"
             )

    assert [[0]] =
             rows("SELECT count(*) FROM phoenix.rails_commands WHERE kind='digests.email_month'")

    [digest] = F.digests(ScratchRepo, 14101)
    [expected] = kase["expected"]["rows"]
    assert digest == Map.put(expected, "id", digest["id"])

    assert [[3]] =
             rows(
               "SELECT calculation_version FROM stats WHERE user_id=14101 AND year=2025 AND month=3"
             )

    assert Generation.run(ScratchRepo, "monthly", args, F.job_options(kase)) == :ok

    assert [[1]] =
             rows(
               "SELECT count(*) FROM phoenix.processed_commands WHERE handler NOT LIKE 'digests.generate_%'"
             )

    assert [[1]] =
             rows("SELECT count(*) FROM phoenix.rails_commands WHERE kind='digests.email_month'")
  end
end
