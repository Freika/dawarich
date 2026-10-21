defmodule Dawarich.CLI.RawDataResetTest do
  use Dawarich.JobsCase

  alias Dawarich.A12eCorpus
  alias Dawarich.RawData.ClearWorker
  alias Dawarich.Wave6Fixtures

  defmodule UnflagRepo do
    alias Dawarich.ScratchRepo

    def query!("UPDATE points SET raw_data_archived = false" <> _ = sql, params, opts) do
      {:ok, result} =
        ScratchRepo.transaction(fn ->
          result = ScratchRepo.query!(sql, params, opts)

          points =
            ScratchRepo.query!("SELECT id, raw_data FROM points ORDER BY id", [], log: false)

          send(Process.get(:unflag_observer), {:unflagged, self(), points.rows})
          receive(do: (:commit -> result))
        end)

      result
    end

    defdelegate query!(sql, params, opts), to: ScratchRepo
    defdelegate transaction(fun), to: ScratchRepo
    defdelegate rollback(reason), to: ScratchRepo
  end

  test "a point cleared by the cron during reset-all stays linked and its archive is kept" do
    c = A12eCorpus.case!("raw_data_reset_all")
    clear = fn -> rows("UPDATE points SET raw_data = '{}'::jsonb WHERE id = 26020") end
    result = A12eCorpus.replay(c, %{before_unflag: clear})

    assert result.exit == 1
    assert result.stderr =~ "still hold points whose raw_data was cleared"

    assert rows(
             "SELECT raw_data_archived, a.month FROM points p JOIN points_raw_data_archives a ON a.id = p.raw_data_archive_id WHERE p.id = 26020"
           ) ==
             [[true, 2]]

    assert rows(
             "SELECT count(*) FROM points WHERE raw_data_archived = false AND raw_data <> '{}'::jsonb"
           ) ==
             [[3]]
  end

  test "an in-flight cron clear rechecks points after reset-all commits its unflag update" do
    c = A12eCorpus.case!("raw_data_reset_all")

    cool = fn ->
      rows("UPDATE points_raw_data_archives SET verified_at = now() - interval '8 days'")
    end

    observer =
      Task.async(fn ->
        receive do
          {:unflagged, holder, points} ->
            [[user]] = rows("SELECT DISTINCT user_id FROM points")
            cron = Task.async(fn -> ClearWorker.run(ScratchRepo, nil, %{"user_id" => user}) end)
            Wave6Fixtures.await_waiter!("UPDATE points SET raw_data = '{}'::jsonb%")
            send(holder, :commit)
            assert Task.await(cron) == :ok
            points
        end
      end)

    Process.put(:unflag_observer, observer.pid)
    result = A12eCorpus.replay(c, %{repo: UnflagRepo, before_unflag: cool})
    points = Task.await(observer)

    assert result.exit == 0
    assert rows("SELECT id, raw_data FROM points ORDER BY id") == points
    assert rows("SELECT count(*) FROM points_raw_data_archives") == [[0]]

    assert rows(
             "SELECT count(*) FROM points WHERE raw_data_archived OR raw_data_archive_id IS NOT NULL"
           ) == [[0]]
  end
end
