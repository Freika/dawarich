defmodule Dawarich.Jobs.SupervisorTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.Jobs.{Claimer, Ownership, Registry}

  @oban Dawarich.NativeRegistryTestOban

  @tag :a12f4_a07_1
  test "standalone registry includes H02 native entries and still respects source ownership" do
    start_oban(@oban)
    entries = Dawarich.Standalone.job_entries(%{"DAWARICH_RAILS" => "off"})
    assert entries == Registry.entries()
    assert Enum.find(entries, &(&1.key == "command:points.tile_epoch"))
    assert Enum.any?(entries, &(&1.claimable == false))

    for entry <- entries, do: Ownership.put!(ScratchRepo, entry.key, :sidekiq, pinned: true)

    before =
      rows(
        "SELECT key, owner, pinned, updated_at, updated_by FROM phoenix.job_owners ORDER BY key"
      )

    {:ok, {_, children}} =
      Dawarich.Jobs.Supervisor.init(
        repo: ScratchRepo,
        oban: @oban,
        entries: entries,
        node: "native-registry-test"
      )

    %{start: {Supervisor, :start_link, [workers, _]}} = Enum.find(children, &(&1.id == :workers))
    {Claimer, opts} = List.keyfind(workers, Claimer, 0)
    assert opts[:entries] == entries
    assert Claimer.run(Keyword.put(opts, :ready?, fn -> true end)) == :ok

    assert rows(
             "SELECT key, owner, pinned, updated_at, updated_by FROM phoenix.job_owners ORDER BY key"
           ) == before

    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
  end
end
