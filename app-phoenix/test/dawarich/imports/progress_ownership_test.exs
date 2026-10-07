defmodule Dawarich.Imports.ProgressOwnershipTest do
  use Dawarich.JobsCase
  alias Dawarich.A12f3bImportsFixture, as: F
  alias Dawarich.Imports.{Events, GpxLifecycle, GpxProgress, Lease, NormalLifecycle, Progress}
  alias Dawarich.Jobs.{Ownership, Registry}

  setup do: F.setup()

  @tag a12f3b_case: "R10progress"
  test "incremental progress respects each native parent and preserves the Rails payload", base do
    for source <- [4, 10], mode <- ["on", "off"], owner <- [:oban, :sidekiq] do
      reset!(ScratchRepo)
      c = Map.merge(base, Dawarich.ImportLeaseFixture.create())
      rows("UPDATE imports SET source=$2 WHERE id=$1", [c.import.id, source])
      own_all()
      Ownership.put!(ScratchRepo, lane(source), owner)
      System.put_env("DAWARICH_RAILS", mode)
      Events.subscribe(c.import.user_id)
      assert %{index: 100} = GpxProgress.record(c.import, 100, %{at: nil, index: 0}, c.context)
      assert_receive :imports_changed
      assert [[100]] == rows("SELECT processed FROM imports WHERE id=$1", [c.import.id])
      assert payloads() == expected(c, mode, owner)

      if owner == :oban do
        Ownership.put!(ScratchRepo, lane(if(source == 4, do: 10, else: 4)), :sidekiq)
        GpxProgress.record(c.import, 200, %{at: nil, index: 0}, c.context)
        assert_receive :imports_changed
        assert [] == payloads()
      end

      unsubscribe(c.import.user_id)
    end
  end

  @tag a12f3b_case: "R10gpx"
  test "GPX lifecycle publishes native terminal progress and retains Rails-owned hand-back",
       base do
    lifecycle(base, 4)
  end

  @tag a12f3b_case: "R10normal"
  test "normal lifecycle publishes native terminal progress and retains Rails-owned hand-back",
       base do
    lifecycle(base, 10)
  end

  defp lifecycle(base, source) do
    for mode <- ["on", "off"] do
      reset!(ScratchRepo)
      c = fixture(base, source)
      terminal = Map.get(c.context, :on_terminal, fn -> :ok end)

      context =
        Map.put(c.context, :on_terminal, fn ->
          terminal.()
          flush_progress()
          :ok
        end)

      c = %{c | context: context}
      own_all()
      System.put_env("DAWARICH_RAILS", mode)
      Events.subscribe(c.import.user_id)
      assert {:ok, :ok} == run(c, source)
      assert_receive :imports_changed
      refute_receive :imports_changed
      assert [[2]] == rows("SELECT status FROM imports WHERE id=$1", [c.import.id])

      assert [["terminal"]] ==
               rows("SELECT phase FROM phoenix.import_runs WHERE import_id=$1", [c.import.id])

      assert [] == rows("SELECT kind FROM phoenix.rails_commands")
      unsubscribe(c.import.user_id)

      Ownership.put!(ScratchRepo, lane(source), :sidekiq)

      assert {:ok, :ok} ==
               ScratchRepo.transaction(fn ->
                 Progress.publish!(ScratchRepo, c.import, c.context.locale)
                 :ok
               end)

      assert payloads() == expected(c, mode, :sidekiq)

      if mode == "on" do
        assert {:skip, :unavailable} == run(c, source)
        assert payloads() == expected(c, mode, :sidekiq)
      end
    end
  end

  defp fixture(base, 4) do
    c = Map.merge(base, Dawarich.ImportLeaseFixture.create())
    F.blob(c, "progress.gpx", "<gpx version='1.1'><trk/></gpx>", "file")

    context =
      Map.merge(c.context, %{
        services: %{"local" => %{service: "local", root: c.root}},
        temp_dir: c.root,
        self_hosted?: true
      })

    %{c | context: context}
  end

  defp fixture(base, 10),
    do: Map.merge(base, Dawarich.Test.NormalFormats.whole!("csv_known", ScratchRepo, base.root))

  defp run(c, 4),
    do: Lease.with_import(ScratchRepo, c.job, c.import, &GpxLifecycle.call(&1, c.context))

  defp run(c, 10),
    do:
      Lease.with_import(
        ScratchRepo,
        c.job,
        c.import,
        &NormalLifecycle.call(&1, c.context),
        Dawarich.Imports.ProcessWorker.lease_options()
      )

  defp lane(4), do: "command:imports.process_gpx"
  defp lane(10), do: "command:imports.process_normal"

  defp own_all do
    for entry <- Registry.entries(), do: Ownership.put!(ScratchRepo, entry.key, :oban)
    assert Enum.all?(rows("SELECT owner FROM phoenix.job_owners"), &(&1 == ["oban"]))
  end

  defp unsubscribe(user) do
    Phoenix.PubSub.unsubscribe(Dawarich.PubSub, "imports:user:#{user}")
    flush_progress()
  end

  defp flush_progress do
    receive do
      :imports_changed -> flush_progress()
    after
      0 -> :ok
    end
  end

  defp payloads,
    do:
      rows(
        "SELECT kind,payload::text FROM phoenix.rails_commands WHERE kind='imports.progress' ORDER BY id"
      )

  defp expected(c, "on", :sidekiq) do
    payload = %{
      "import_id" => c.import.id,
      "user_id" => c.import.user_id,
      "locale" => c.context.locale
    }

    [["imports.progress", jsonb_text(payload)]]
  end

  defp expected(_, _, _), do: []
  defp jsonb_text(payload), do: rows("SELECT $1::jsonb::text", [payload]) |> hd() |> hd()
end
