defmodule Dawarich.Jobs.JointOwnershipTest.InvalidJob do
  @moduledoc false
  def new(args), do: Oban.Job.new(args, worker: Dawarich.Lite.ArchivalWarningWorker, priority: 99)
end

defmodule Dawarich.Jobs.JointOwnershipTest do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.{Claimer, Ownership, Registry}

  @keys ~w(command:mail.user.archival_approaching cron:lite_archival_warning_job)
  @oban __MODULE__.Oban

  setup do
    start_oban(@oban)
    :ok
  end

  defp owners, do: rows("SELECT key, owner, pinned FROM phoenix.job_owners ORDER BY key")
  defp entry(key), do: Enum.find(Registry.entries(), &(&1.key == key))

  test "joint Lite ownership changes atomically and source batches cannot cross a native flip" do
    for key <- @keys do
      Ownership.put!(ScratchRepo, key, :oban)
      assert owners() == Enum.map(@keys, &[&1, "oban", false])
      Ownership.put!(ScratchRepo, key, :sidekiq, pinned: true)
      assert owners() == Enum.map(@keys, &[&1, "sidekiq", true])
      assert Claimer.claim(ScratchRepo, @oban, entry(key)) == :pinned
    end

    rows("UPDATE phoenix.job_owners SET pinned = false")
    rows("UPDATE phoenix.job_owners SET pinned = true WHERE key = $1", [hd(@keys)])
    assert Claimer.claim(ScratchRepo, @oban, entry(List.last(@keys))) == :pinned
    assert owners() == [[hd(@keys), "sidekiq", true], [List.last(@keys), "sidekiq", false]]
    rows("UPDATE phoenix.job_owners SET pinned = false")

    invalid =
      entry(List.last(@keys))
      |> Map.put(:catch_up, true)
      |> Map.put(:worker, __MODULE__.InvalidJob)

    assert Claimer.claim(ScratchRepo, @oban, invalid) == {:error, :catch_up_insert}
    assert owners() == Enum.map(@keys, &[&1, "sidekiq", false])
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]

    parent = self()

    source =
      Task.async(fn ->
        Ownership.with_owner(ScratchRepo, List.last(@keys), :sidekiq, fn ->
          rows(
            "INSERT INTO phoenix.runtime_nodes (node, started_at, beat_at) VALUES ('first-batch', now(), now())"
          )

          send(parent, :holding)

          receive do
            :release -> :published
          end
        end)
      end)

    try do
      assert_receive :holding

      assert Claimer.claim(ScratchRepo, @oban, entry(hd(@keys)), "50ms") ==
               {:error, :lock_not_available}
    after
      send(source.pid, :release)
      assert Task.await(source) == {:ok, :published}
    end

    assert Claimer.claim(ScratchRepo, @oban, entry(hd(@keys))) == :claimed
    assert owners() == Enum.map(@keys, &[&1, "oban", false])

    assert Ownership.with_owner(ScratchRepo, List.last(@keys), :sidekiq, fn ->
             flunk("late source batch")
           end) == {:skip, :oban}

    Ownership.put!(ScratchRepo, hd(@keys), :sidekiq, pinned: true)
    assert owners() == Enum.map(@keys, &[&1, "sidekiq", true])
  end

  test "a first source effect fences the first native claim even when its ownership row was absent" do
    key = "command:imports.teslamate_sync"
    parent = self()

    source =
      Task.async(fn ->
        Ownership.with_owner(ScratchRepo, key, :sidekiq, fn ->
          send(parent, :holding)

          receive do
            :release -> :published
          end
        end)
      end)

    try do
      assert_receive :holding

      assert Claimer.claim(ScratchRepo, @oban, entry(key), "50ms") ==
               {:error, :lock_not_available}
    after
      send(source.pid, :release)
      assert Task.await(source) == {:ok, :published}
    end

    assert Claimer.claim(ScratchRepo, @oban, entry(key)) == :claimed

    assert Ownership.with_owner(ScratchRepo, key, :sidekiq, fn -> flunk("late source effect") end) ==
             {:skip, :oban}
  end
end
