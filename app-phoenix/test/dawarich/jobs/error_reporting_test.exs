defmodule Dawarich.Jobs.ErrorReportingTest do
  use Dawarich.ErrorReportingCase, async: false
  use Dawarich.JobsCase, async: false

  defmodule FailingWorker do
    use Oban.Worker, queue: :maintenance, max_attempts: 2
    def perform(%Oban.Job{args: args}), do: raise(inspect(args))
  end

  test "an executing Oban job exception reports once per failure with safe metadata and normal retry state" do
    name = __MODULE__.Oban
    start_oban(name)

    {:ok, job} =
      Oban.insert(
        name,
        FailingWorker.new(%{
          "email" => "victim@example.invalid",
          "payload" => "private-job",
          "otp" => "654321"
        })
      )

    assert %{failure: 1, success: 0} =
             Oban.drain_queue(name, queue: :maintenance, with_safety: true)

    {_item, first} = envelope()

    assert first["tags"] == %{
             "surface" => "oban",
             "worker" => inspect(FailingWorker),
             "queue" => "maintenance",
             "attempt" => 1,
             "max_attempts" => 2
           }

    assert hd(first["exception"])["type"] == "RuntimeError"
    assert hd(first["exception"])["stacktrace"]["frames"] != []
    assert_private(first)

    assert [["retryable", 1]] =
             rows("SELECT state, attempt FROM oban.oban_jobs WHERE id=$1", [job.id])

    refute_receive {:envelope, _, _}

    assert %{discard: 1, failure: 0, success: 0} =
             Oban.drain_queue(name, queue: :maintenance, with_safety: true, with_scheduled: true)

    {_item, second} = envelope()
    assert second["tags"]["attempt"] == 2
    assert_private(second)

    assert [["discarded", 2]] =
             rows("SELECT state, attempt FROM oban.oban_jobs WHERE id=$1", [job.id])

    refute_receive {:envelope, _, _}
  end
end
