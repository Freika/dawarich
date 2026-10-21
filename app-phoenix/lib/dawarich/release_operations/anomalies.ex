defmodule Dawarich.ReleaseOperations.Anomalies do
  @moduledoc false
  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 26

  alias Dawarich.ReleaseOperations, as: Ops
  alias Dawarich.ReleaseOperations.{AnomalyClaims, AnomaliesUser}
  alias Dawarich.Users.RecalculationArgs

  def command_type, do: "release.anomalies"

  def args_from_command(version, payload) do
    with {:ok, request} <- RecalculationArgs.decode(command_type(), version, payload),
         do: {:ok, %{"version" => 1, "cursor" => %{"request" => request, "pass" => 0}}}
  end

  @impl Oban.Worker
  def perform(%Oban.Job{conf: conf} = job),
    do: Ops.run(Dawarich.Jobs.repo(), conf.name, __MODULE__, job)

  def step(repo, %{cursor: %{"request" => request} = cursor} = op) do
    now = Keyword.get_lazy(op.opts, :now, &DateTime.utc_now/0)
    {runnable, skipped} = AnomalyClaims.next_users(repo, request["limit"], now)
    if hook = op.opts[:after_scan], do: hook.(runnable)

    Ops.commit(repo, op, fn ->
      AnomalyClaims.settle(repo, skipped, now)
      claimed = AnomalyClaims.claim(repo, runnable, now)

      for id <- claimed do
        source = Ecto.UUID.generate()

        {:ok, args} =
          AnomaliesUser.args_from_command(1, %{
            "user_id" => id,
            "attempt" => 1,
            "source_job_id" => source,
            "ambient_zone" => request["ambient_zone"]
          })

        Oban.insert!(op.oban, AnomaliesUser.new(Map.put(args, "event_id", source)))
        if hook = op.opts[:after_child], do: hook.(id)
      end

      if claimed == [] and (runnable != [] or skipped != []),
        do: {Map.update!(cursor, "pass", &(&1 + 1)), 0},
        else: :done
    end)
  end
end
