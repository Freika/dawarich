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
      assert :ok == ProcessWorker.perform(late)
      assert [[2000]] == progress(c)
      assert [[1003, 0, 0, 1003]] == counts(c)
      assert [[3]] == rows("SELECT count(*) FROM phoenix.processed_commands")
    end

    @tag deferred_continuation: true
    test "a deferred continuation survives a newer successor arriving before its retry (#{mode})",
         c do
      if @mode == "coexistence", do: System.delete_env("DAWARICH_RAILS")
      first = job(c, Enum.map(0..1000, &location/1), 1000)
      second = job(c, [location(2000)], 2000)
      third = job(c, [location(3000)], 3000)
      interrupt(first)
      assert {:snooze, 5} == ProcessWorker.perform(second)
      rows("UPDATE oban.oban_jobs SET state='scheduled' WHERE id=$1", [second.id])
      assert :ok == ProcessWorker.perform(retry(first))
      assert [[1001, 0, 0, 1001]] == counts(c)
      assert {:snooze, 5} == ProcessWorker.perform(third)
      assert [[1000]] == progress(c)
      assert :ok == ProcessWorker.perform(retry(second))
      assert [[2000]] == progress(c)
      assert :ok == ProcessWorker.perform(retry(third))
      assert [[3000]] == progress(c)
      assert [[1003, 0, 0, 1003]] == counts(c)

      assert [[1]] ==
               rows("SELECT count(*) FROM points WHERE import_id=$1 AND timestamp=$2", [
                 c.import.id,
                 1_768_521_800
               ])

      for current <- [first, second, third] do
        assert Dawarich.Jobs.Processed.done?(ScratchRepo, current.args["event_id"])
        assert :ok == ProcessWorker.perform(retry(current))
        assert [[1003, 0, 0, 1003]] == counts(c)
      end
    end

    @tag continuation_interleavings: true
    test "arbitrary continuation interleavings import the source total exactly once (#{mode})",
         c do
      if @mode == "coexistence", do: System.delete_env("DAWARICH_RAILS")

      for order <- permutations([0, 1, 2, 3]) do
        reset!(ScratchRepo)
        c = Map.merge(c, Dawarich.ImportLeaseFixture.create())
        rows("UPDATE imports SET source=2 WHERE id=$1", [c.import.id])
        Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:imports.process_normal", :oban)
        chunks = Enum.map(0..3, fn i -> Enum.map((i * 3)..(i * 3 + 2), &location/1) end)

        jobs =
          Enum.zip(chunks, [1000, 2000, 2000, 3000])
          |> Enum.map(fn {chunk, index} -> job(c, chunk, index) end)

        first = hd(jobs)
        rows("UPDATE oban.oban_jobs SET state='scheduled' WHERE id=$1", [first.id])

        Enum.reduce(order, 0, fn position, previous ->
          current = Enum.at(jobs, position)
          rows("UPDATE oban.oban_jobs SET state='executing' WHERE id=$1", [current.id])

          pending =
            Enum.find(jobs, fn candidate ->
              not Dawarich.Jobs.Processed.done?(ScratchRepo, candidate.args["event_id"])
            end)

          expected = if is_nil(pending) or pending.id == current.id, do: :ok, else: {:snooze, 5}
          assert expected == ProcessWorker.perform(current)
          [[value]] = progress(c)
          assert value >= previous
          value
        end)

        for current <- jobs do
          assert :ok == ProcessWorker.perform(retry(current))
        end

        assert [[12, 0, 0, 12]] == counts(c)
        assert [[3000]] == progress(c)
        assert [[4]] == rows("SELECT count(*) FROM phoenix.processed_commands")

        assert Enum.map(0..11, &[1_768_519_800 + &1]) ==
                 rows("SELECT timestamp FROM points WHERE import_id=$1 ORDER BY timestamp", [
                   c.import.id
                 ])

        for position <- order do
          assert :ok == ProcessWorker.perform(retry(Enum.at(jobs, position)))
          assert [[12, 0, 0, 12]] == counts(c)
          assert [[3000]] == progress(c)
        end
      end
    end

    @tag continuation_late: true
    test "a late lower-index continuation remains work instead of cancellation (#{mode})", c do
      if @mode == "coexistence", do: System.delete_env("DAWARICH_RAILS")
      first = job(c, [location(2000)], 2000)
      assert :ok == ProcessWorker.perform(first)
      late = job(c, [location(1000)], 1000)
      assert :ok == ProcessWorker.perform(late)
      assert [[2000]] == progress(c)
      assert [[2, 0, 0, 2]] == counts(c)
      assert Dawarich.Jobs.Processed.done?(ScratchRepo, late.args["event_id"])
      assert :ok == ProcessWorker.perform(retry(late))
      assert [[2, 0, 0, 2]] == counts(c)
    end

    @tag continuation_legacy_order: true
    test "legacy receipts without job ids keep equal-index pending work executable (#{mode})",
         c do
      if @mode == "coexistence", do: System.delete_env("DAWARICH_RAILS")
      earlier = job(c, [location(2000)], 1000)
      later = job(c, Enum.map(0..1000, &location/1), 1000)

      rows("UPDATE oban.oban_jobs SET worker='Dawarich.Imports.ProcessGpxWorker' WHERE id=$1", [
        earlier.id
      ])

      interrupt(later)

      rows("UPDATE oban.oban_jobs SET worker='Dawarich.Imports.ProcessWorker' WHERE id=$1", [
        earlier.id
      ])

      rows(
        "UPDATE phoenix.import_runs SET attachment_snapshot=attachment_snapshot #- ARRAY['events',$1,'job_id']",
        [later.args["event_id"]]
      )

      assert [[1000, 0, 0, 1000]] == counts(c)
      assert {:snooze, 5} == ProcessWorker.perform(retry(later))
      assert :ok == ProcessWorker.perform(earlier)
      assert :ok == ProcessWorker.perform(retry(later))
      assert [[1002, 0, 0, 1002]] == counts(c)
      assert [[1000]] == progress(c)

      for current <- [earlier, later] do
        assert :ok == ProcessWorker.perform(retry(current))
        assert [[1002, 0, 0, 1002]] == counts(c)
      end
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

  defp permutations([]), do: [[]]

  defp permutations(items),
    do: for(item <- items, tail <- permutations(items -- [item]), do: [item | tail])

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
    rows("UPDATE oban.oban_jobs SET state='executing',attempt=2 WHERE id=$1", [job.id])
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
