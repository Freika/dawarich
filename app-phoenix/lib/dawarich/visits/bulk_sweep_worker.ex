defmodule Dawarich.Visits.BulkSweepWorker do
  @moduledoc false
  use Oban.Worker, queue: :visit_suggesting, max_attempts: 1

  alias Dawarich.Visits.{BulkSweep, Calendar}

  def key, do: "cron:visit_suggesting_job"

  def args_from_command(
        1,
        %{"start_at" => a, "end_at" => b, "user_ids" => ids, "time_zone" => zone} = p
      )
      when map_size(p) == 4 and is_binary(a) and is_binary(b) and is_list(ids) and is_binary(zone) do
    if Enum.all?(ids, &(is_integer(&1) and &1 > 0)) and
         match?({:ok, _, _}, DateTime.from_iso8601(a)) and
         match?({:ok, _, _}, DateTime.from_iso8601(b)),
       do: {:ok, p},
       else: {:error, "invalid_payload"}
  end

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def new(%{"event_id" => _} = args, opts),
    do:
      super(
        args,
        Keyword.put(opts, :unique, keys: [:event_id, :after_id], states: :all, period: :infinity)
      )

  def new(args, opts), do: super(args, opts)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => _} = args, conf: conf}),
    do: run(Dawarich.Jobs.repo(), conf.name, args)

  def perform(%Oban.Job{inserted_at: at, conf: conf}),
    do: run_cron(Dawarich.Jobs.repo(), conf.name, div(DateTime.to_unix(at), 60) * 60)

  def run(repo, oban, args, opts \\ []), do: BulkSweep.run(repo, oban, args, opts)

  def run_cron(repo, oban, slot, opts \\ []) do
    env = Keyword.get_lazy(opts, :env, &System.get_env/0)

    zone =
      Keyword.get(
        opts,
        :time_zone,
        Dawarich.TimeZoneName.to_iana(env["TIME_ZONE"] || "Europe/Berlin")
      )

    {start, stop} = Calendar.previous_day(repo, zone, slot)

    args = %{
      "event_id" => BulkSweep.cron_id(slot),
      "start_at" => start,
      "end_at" => stop,
      "user_ids" => [],
      "time_zone" => zone,
      "cron" => true
    }

    run(repo, oban, args, opts)
  end
end
