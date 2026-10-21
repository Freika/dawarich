defmodule Dawarich.RawData.ClearWorkerTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.Jobs.Ownership
  alias Dawarich.{Wave6Archives, Wave6Fixtures}
  alias Dawarich.RawData.ClearWorker

  @moduletag :capture_log
  @oban Dawarich.RawData.ClearWorkerTest.Oban

  setup do
    Wave6Fixtures.reset!()
    start_oban(@oban)
    %{user: Wave6Fixtures.user!()}
  end

  defp verified_archive!(user, days_ago, chunk \\ 1) do
    verified_at = NaiveDateTime.add(NaiveDateTime.utc_now(), -days_ago * 86_400)
    Wave6Archives.archive!(user, %{"verified_at" => verified_at, "chunk_number" => chunk})
  end

  defp linked!(user, archive_id, n) do
    Wave6Fixtures.point!(user, %{
      "raw_data" => %{"n" => n},
      "raw_data_archived" => true,
      "raw_data_archive_id" => archive_id
    })
  end

  defp raw_data, do: rows("SELECT id, raw_data FROM points ORDER BY id")

  defp run(args, opts \\ []), do: ClearWorker.run(ScratchRepo, @oban, args, opts)

  test "clear_respects_cooling_period", %{user: user} do
    cooled = linked!(user, verified_archive!(user, 8), 1)
    fresh = linked!(user, verified_archive!(user, 2, 2), 2)

    assert run(%{"user_id" => user}) == :ok

    assert raw_data() == [[cooled, %{}], [fresh, %{"n" => 2}]]
  end

  test "clear_does_not_touch_unlinked_points", %{user: user} do
    stranger = Wave6Fixtures.user!()
    unarchived = Wave6Fixtures.point!(user, %{"raw_data" => %{"n" => 1}})
    foreign = linked!(user, verified_archive!(stranger, 8), 2)

    assert run(%{"user_id" => user}) == :ok

    assert raw_data() == [[unarchived, %{"n" => 1}], [foreign, %{"n" => 2}]]
  end

  test "clear_rechecks_verification_per_batch", %{user: user} do
    archive = verified_archive!(user, 8)
    linked!(user, archive, 1)
    linked!(user, archive, 2)

    unverify = fn ->
      ScratchRepo.query!("UPDATE points_raw_data_archives SET verified_at = NULL WHERE id = $1", [
        archive
      ])
    end

    assert run(%{"user_id" => user}, batch_size: 1, after_batch: unverify) == :ok

    assert raw_data() |> Enum.count(fn [_id, raw] -> raw == %{} end) == 1
  end

  test "clear_batches_advance_past_the_last_cleared_id", %{user: user} do
    archive = verified_archive!(user, 8)
    [first, second, third] = for n <- 1..3, do: linked!(user, archive, n)

    rewrite = fn ->
      if Process.delete(:first_batch),
        do: ScratchRepo.query!("UPDATE points SET raw_data = '{\"n\": 1}' WHERE id = $1", [first])
    end

    Process.put(:first_batch, true)
    assert run(%{"user_id" => user}, batch_size: 1, after_batch: rewrite) == :ok

    assert raw_data() == [[first, %{"n" => 1}], [second, %{}], [third, %{}]]
  end

  test "clear_rejects_malformed_args_instead_of_sweeping" do
    Ownership.put!(ScratchRepo, ClearWorker.key(), :oban)

    for args <- [%{"user_id" => "5"}, %{"user_id" => nil}, %{"x" => 1}] do
      assert run(args, enabled: true) == {:cancel, :invalid_args}
    end

    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
  end

  test "clear_cron_is_gated_by_env_and_owner", %{user: user} do
    other = Wave6Fixtures.user!()
    Wave6Fixtures.user!(%{"deleted_at" => NaiveDateTime.utc_now()})
    jobs = fn -> rows("SELECT worker, args FROM oban.oban_jobs ORDER BY id") end

    assert run(%{}, enabled: false) == :ok
    assert jobs.() == []

    assert run(%{}, enabled: true) == {:cancel, :not_owner}
    assert jobs.() == []

    Ownership.put!(ScratchRepo, ClearWorker.key(), :oban)
    assert run(%{}, enabled: true) == :ok

    assert jobs.() == [
             ["Dawarich.RawData.ClearWorker", %{"user_id" => user}],
             ["Dawarich.RawData.ClearWorker", %{"user_id" => other}]
           ]
  end
end
