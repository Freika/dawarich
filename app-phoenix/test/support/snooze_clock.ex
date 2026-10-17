defmodule Dawarich.Test.SnoozeClock do
  @moduledoc false

  defmodule DelayedAttemptEngine do
    @moduledoc false
    @behaviour Oban.Engine
    import Ecto.Query

    for {name, arity} <- Oban.Engines.Basic.__info__(:functions), name != :fetch_jobs do
      args = Macro.generate_arguments(arity, __MODULE__)
      defdelegate unquote(name)(unquote_splicing(args)), to: Oban.Engines.Basic
    end

    def fetch_jobs(conf, meta, running) do
      {:ok, {meta, jobs}} = Oban.Engines.Basic.fetch_jobs(conf, meta, running)

      jobs =
        Enum.map(jobs, fn job ->
          attempted_at = DateTime.add(job.attempted_at, -1, :second)
          query = where(Oban.Job, id: ^job.id)
          {1, _} = Oban.Repo.update_all(conf, query, set: [attempted_at: attempted_at])
          %{job | attempted_at: attempted_at}
        end)

      {:ok, {meta, jobs}}
    end
  end

  def drain_queue(oban, opts) do
    clock =
      Task.async(fn ->
        receive do
          {:trace, _, :return_from, {DateTime, :utc_now, 0}, now} -> now
        end
      end)

    session = :trace.session_create(__MODULE__, clock.pid, [])
    handler = {__MODULE__, make_ref()}

    :trace.function(session, {DateTime, :utc_now, 0}, [{:_, [], [{:return_trace}]}], [:local])

    :ok =
      :telemetry.attach(
        handler,
        [:oban, :engine, :snooze_job, :start],
        &__MODULE__.observe/4,
        {oban, session}
      )

    try do
      conf = %{Oban.config(oban) | engine: DelayedAttemptEngine}
      result = Oban.Queues.Drainer.drain(conf, opts)
      {result, Task.await(clock)}
    after
      :telemetry.detach(handler)
      :trace.session_destroy(session)
      Task.shutdown(clock, :brutal_kill)
    end
  end

  def observe(_, _, %{conf: %{name: oban}}, {oban, session}) do
    :trace.process(session, self(), true, [:call])
  end

  def observe(_, _, _, _), do: :ok
end
