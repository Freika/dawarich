defmodule Dawarich.Jobs.ErrorReportingTest do
  use Dawarich.ErrorReportingCase, async: false
  use Dawarich.JobsCase, async: false

  defmodule FailingWorker do
    use Oban.Worker, queue: :maintenance, max_attempts: 2
    def perform(%Oban.Job{args: args}), do: raise(inspect(args))
  end

  defmodule ReturnedErrorWorker do
    use Oban.Worker, queue: :maintenance, max_attempts: 2
    def perform(%Oban.Job{args: args}), do: {:error, RuntimeError.exception(inspect(args))}
  end

  test "an executing Oban returned error reports once per attempt without a stack and preserves retry and discard states" do
    name = __MODULE__.ReturnedErrorOban
    start_oban(name)

    {:ok, job} =
      Oban.insert(
        name,
        ReturnedErrorWorker.new(%{
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
             "worker" => inspect(ReturnedErrorWorker),
             "queue" => "maintenance",
             "attempt" => 1,
             "max_attempts" => 2
           }

    assert hd(first["exception"])["type"] == "RuntimeError"
    assert hd(first["exception"])["value"] == "[FILTERED]"
    refute Map.has_key?(hd(first["exception"]), "stacktrace")
    assert_private(first)

    assert [["retryable", 1]] =
             rows("SELECT state, attempt FROM oban.oban_jobs WHERE id=$1", [job.id])

    refute_receive {:envelope, _, _}

    assert %{discard: 1, failure: 0, success: 0} =
             Oban.drain_queue(name, queue: :maintenance, with_safety: true, with_scheduled: true)

    {_item, second} = envelope()
    assert second["tags"] == %{first["tags"] | "attempt" => 2}
    assert hd(second["exception"])["type"] == "RuntimeError"
    assert hd(second["exception"])["value"] == "[FILTERED]"
    refute Map.has_key?(hd(second["exception"]), "stacktrace")
    assert_private(second)

    assert [["discarded", 2]] =
             rows("SELECT state, attempt FROM oban.oban_jobs WHERE id=$1", [job.id])

    refute_receive {:envelope, _, _}
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
