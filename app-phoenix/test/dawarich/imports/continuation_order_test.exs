defmodule Dawarich.Imports.ContinuationOrderTest do
  use Dawarich.JobsCase
  alias Dawarich.A12f3bImportsFixture, as: F
  alias Dawarich.Imports.ProcessWorker

  setup do
    c = F.setup()
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:imports.process_normal", :oban)
    rows("UPDATE imports SET source=2 WHERE id=$1", [c.import.id])
    c
  end

  for mode <- ["off", "coexistence"] do
    @mode mode
    @tag continuation_order: true
    test "continuation events cannot overtake an incomplete predecessor (#{mode})", c do
      if @mode == "coexistence", do: System.delete_env("DAWARICH_RAILS")
      first = job(c, Enum.map(0..1000, &location/1), 1000)
      second = job(c, [location(2000)], 2000)
      interrupt(first)
      assert [[1000, 0, 0, 1000]] == counts(c)
      assert [[1000]] == progress(c)
      assert [[0]] == rows("SELECT count(*) FROM phoenix.processed_commands")
      receipt = rows("SELECT event_id,attachment_snapshot FROM phoenix.import_runs")

      assert {:snooze, 5} == ProcessWorker.perform(second)
      assert receipt == rows("SELECT event_id,attachment_snapshot FROM phoenix.import_runs")
      assert [[1000, 0, 0, 1000]] == counts(c)
      assert [[1000]] == progress(c)
      refute Dawarich.Jobs.Processed.done?(ScratchRepo, second.args["event_id"])

      assert :ok == ProcessWorker.perform(retry(first))
      assert [[1001, 0, 0, 1001]] == counts(c)
      assert [[1000]] == progress(c)
      assert :ok == ProcessWorker.perform(retry(second))
      assert [[1002, 0, 0, 1002]] == counts(c)
      assert [[2000]] == progress(c)

      for current <- [retry(first), retry(second)] do
        assert :ok == ProcessWorker.perform(current)
        assert [[2000]] == progress(c)
        assert [[1002, 0, 0, 1002]] == counts(c)
      end

      late = job(c, [location(3000)], 500)
      assert {:cancel, "out-of-order continuation"} == ProcessWorker.perform(late)
      assert [[2000]] == progress(c)
      assert [[1002, 0, 0, 1002]] == counts(c)
      assert [[2]] == rows("SELECT count(*) FROM phoenix.processed_commands")
    end

    @tag continuation_progress: true
    test "retrying a predecessor never lowers durable import progress (#{mode})", c do
      if @mode == "coexistence", do: System.delete_env("DAWARICH_RAILS")
      first = job(c, Enum.map(0..1000, &location/1), 1000)
      interrupt(first)
      assert [[1000, 0, 0, 1000]] == counts(c)
      rows("UPDATE imports SET processed=2000 WHERE id=$1", [c.import.id])

      current = retry(first)
      assert :ok == ProcessWorker.perform(current)
      assert [[2000]] == progress(c)
      assert [[1001, 0, 0, 1001]] == counts(c)
      assert :ok == ProcessWorker.perform(current)
      assert [[2000]] == progress(c)
      assert [[1001, 0, 0, 1001]] == counts(c)
      assert [[1]] == rows("SELECT count(*) FROM phoenix.processed_commands")
    end
  end

  defp location(index) do
    %{
      "latitudeE7" => 513_000_000,
      "longitudeE7" => 124_000_000,
      "timestamp" => DateTime.to_iso8601(DateTime.from_unix!(1_768_519_800 + index))
    }
  end

  defp job(c, locations, index) do
    args =
      c.job.args
      |> Map.put("event_id", Ecto.UUID.generate())
      |> Map.put("continuation", %{"locations" => locations, "current_index" => index})

    [[id]] =
      rows(
        "INSERT INTO oban.oban_jobs(worker,args,queue,state,attempt,max_attempts) VALUES('Dawarich.Imports.ProcessWorker',$1,'imports','executing',1,3) RETURNING id",
        [args]
      )

    %Oban.Job{id: id, args: args, attempt: 1, max_attempts: 3, meta: %{}}
  end

  defp retry(job) do
    rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [job.id])
    %{job | attempt: 2}
  end

  defp interrupt(job) do
    rows("""
    CREATE FUNCTION public.continuation_order_interrupt() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF NEW.timestamp=1768520800 THEN
        RAISE EXCEPTION 'synthetic second batch interruption';
      END IF;
      RETURN NEW;
    END $$
    """)

    rows("""
    CREATE TRIGGER continuation_order_interrupt BEFORE INSERT ON points
    FOR EACH ROW EXECUTE FUNCTION public.continuation_order_interrupt()
    """)

    try do
      assert_raise Postgrex.Error, fn -> ProcessWorker.perform(job) end
    after
      rows("DROP TRIGGER IF EXISTS continuation_order_interrupt ON points")
      rows("DROP FUNCTION IF EXISTS public.continuation_order_interrupt()")
    end
  end

  defp counts(c) do
    rows(
      "SELECT raw_points,doubles,points_count,(SELECT count(*) FROM points WHERE import_id=i.id) FROM imports i WHERE id=$1",
      [c.import.id]
    )
  end

  defp progress(c), do: rows("SELECT processed FROM imports WHERE id=$1", [c.import.id])
end
