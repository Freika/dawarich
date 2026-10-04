defmodule Dawarich.CLI.JobsTest do
  use Dawarich.JobsCase

  alias Dawarich.{CLI, ScratchRepo}

  @oban Dawarich.CLI.JobsTest.Oban

  defmodule BrokenRepo do
    def transaction(_fun), do: raise(DBConnection.ConnectionError, "connection refused")
  end

  defp run(argv, extra \\ %{}) do
    {:ok, out} = StringIO.open("")
    {:ok, err} = StringIO.open("")
    ctx = Map.merge(%{repo: ScratchRepo, out: out, err: err, stdin: out, env: %{}}, extra)

    {CLI.run(argv, ctx), out |> StringIO.contents() |> elem(1),
     err |> StringIO.contents() |> elem(1)}
  end

  test "status answers unknown when the database fails" do
    assert {0, out, ""} = run(~w(jobs status), %{repo: BrokenRepo})

    assert Jason.decode!(out) == %{
             "summary" => %{"status" => "unknown", "alarm" => false},
             "gauges" => %{"tables" => "unknown"}
           }
  end

  test "status counts Oban jobs per worker and state" do
    start_oban(@oban)
    Oban.insert!(@oban, Dawarich.Jobs.TestEchoWorker.new(%{"n" => 1}))
    {0, out, ""} = run(~w(jobs status))

    assert [%{"worker" => "Dawarich.Jobs.TestEchoWorker", "state" => "available", "count" => 1}] =
             Jason.decode!(out)["gauges"]["oban"]
  end

  test "resume re-enqueues a failed release operation and refuses anything else" do
    start_oban(@oban)
    id = Ecto.UUID.generate()

    ScratchRepo.query!(
      "INSERT INTO phoenix.release_operations (id, command_type, cursor, status) VALUES ($1, 'release.route_opacity', '{\"after_id\": 0}', 'failed')",
      [Ecto.UUID.dump!(id)]
    )

    assert {0, "#{id}: resumed\n", ""} == run(["jobs", "resume", id], %{oban: @oban})
    assert [[%{"operation_id" => ^id}]] = rows("SELECT args FROM oban.oban_jobs")
    assert {1, "", err} = run(["jobs", "resume", Ecto.UUID.generate()], %{oban: @oban})
    assert err =~ "is not a failed or stalled release operation"
  end

  test "resume without an injected Oban starts its own idle instance and enqueues there" do
    id = Ecto.UUID.generate()

    ScratchRepo.query!(
      "INSERT INTO phoenix.release_operations (id, command_type, cursor, status) VALUES ($1, 'release.route_opacity', '{\"after_id\": 0}', 'failed')",
      [Ecto.UUID.dump!(id)]
    )

    assert {0, "#{id}: resumed\n", ""} == run(["jobs", "resume", id])

    assert [[%{"operation_id" => ^id}]] = rows("SELECT args FROM oban.oban_jobs")
  end

  test "resume refuses an id that is not a UUID with the usage" do
    assert {1, "", "dawarich: usage: dawarich jobs resume OPERATION_ID\n"} =
             run(~w(jobs resume 42), %{oban: @oban})
  end
end
