defmodule Dawarich.Imports.AcceptedDispositionTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.{ProcessWorker, ProcessGpxWorker}
  alias Dawarich.Jobs.{Ownership, Processed, Registry}
  alias Dawarich.Test.NormalFormats

  setup do
    root = Path.join(System.tmp_dir!(), "accepted-import-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)
    old_mode = System.get_env("DAWARICH_RAILS")
    old_repo = Application.fetch_env(:dawarich, :jobs_repo)
    old_services = Application.fetch_env(:dawarich, :imports_services)
    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)

    Application.put_env(:dawarich, :imports_services, %{
      "local" => %{service: "local", root: root}
    })

    on_exit(fn ->
      if old_mode,
        do: System.put_env("DAWARICH_RAILS", old_mode),
        else: System.delete_env("DAWARICH_RAILS")

      restore(:jobs_repo, old_repo)
      restore(:imports_services, old_services)
      File.rm_rf!(root)
    end)

    %{root: root}
  end

  for name <-
        ~w(zip_unsafe_skip zip_duplicate_entries bounded_tcx_nodes bounded_csv_line bounded_rec_line),
      mode <- ["on", "off"] do
    @tag disposition_case: name
    test "accepted #{name} has an executor with fixed native ownership in #{mode}",
         c do
      mode = unquote(mode)

      (fn ->
         reset!(ScratchRepo)
         System.put_env("DAWARICH_RAILS", mode)
         c = Map.merge(c, NormalFormats.whole!(unquote(name), ScratchRepo, c.root))
         assert c.expected["points"] != [] or c.expected["children"] != []
         execute(c, ProcessWorker, "imports.process_normal", "imports.normal_resume", mode)
       end).()
    end
  end

  for {worker, source, lane, kind} <- [
        {ProcessWorker, 4, "imports.process_normal", "imports.normal_resume"},
        {ProcessGpxWorker, 6, "imports.process_gpx", "imports.resume"}
      ],
      mode <- ["on", "off"] do
    @tag disposition_case: lane
    test "accepted #{lane} changed source has an executor with fixed ownership in #{mode}",
         _c do
      mode = unquote(mode)

      (fn ->
         reset!(ScratchRepo)
         System.put_env("DAWARICH_RAILS", mode)
         c = Dawarich.ImportLeaseFixture.create()
         rows("UPDATE imports SET source=$2,status=1 WHERE id=$1", [c.import.id, unquote(source)])

         rows("UPDATE oban.oban_jobs SET worker=$2 WHERE id=$1", [
           c.job.id,
           String.trim_leading(Atom.to_string(unquote(worker)), "Elixir.")
         ])

         execute(c, unquote(worker), unquote(lane), unquote(kind), mode)
       end).()
    end
  end

  defp execute(c, worker, lane, _kind, _mode) do
    for entry <- Registry.entries(), do: Ownership.put!(ScratchRepo, entry.key, :oban)

    rows("UPDATE users SET settings=jsonb_build_object('locale','fr') WHERE id=$1", [
      c.import.user_id
    ])

    rows("UPDATE oban.oban_jobs SET state='available',attempt=0 WHERE id=$1", [c.job.id])
    start_oban(__MODULE__)

    assert %{success: 1, failure: 0, cancelled: 0, snoozed: 0, discard: 0} =
             Oban.drain_queue(__MODULE__, queue: :imports)

    assert [["completed", 1]] ==
             rows("SELECT state,attempt FROM oban.oban_jobs WHERE id=$1", [c.job.id])

    assert [["oban"]] ==
             rows("SELECT owner FROM phoenix.job_owners WHERE key=$1", ["command:" <> lane])

    assert Processed.done?(ScratchRepo, c.job.args["event_id"])
    assert [] == rows("SELECT id FROM points WHERE import_id=$1", [c.import.id])

    assert [] == rows("SELECT kind FROM phoenix.rails_commands")
    assert [] == rows("SELECT event_id FROM phoenix.import_handoffs")

    assert [[3, message]] =
             rows("SELECT status,error_message FROM imports WHERE id=$1", [c.import.id])

    assert is_binary(message) and message != ""

    assert [[2, title, content]] =
             rows("SELECT kind,title,content FROM notifications WHERE user_id=$1", [
               c.import.user_id
             ])

    assert title =~ "échoué"
    assert content != ""

    before =
      rows("SELECT status,raw_points,doubles,error_message FROM imports WHERE id=$1", [
        c.import.id
      ])

    for attempt <- 2..3 do
      assert :ok == worker.perform(%{c.job | attempt: attempt})

      assert before ==
               rows("SELECT status,raw_points,doubles,error_message FROM imports WHERE id=$1", [
                 c.import.id
               ])
    end

    assert [[0]] ==
             rows("SELECT count(*) FROM phoenix.rails_commands")

    assert [[1]] ==
             rows("SELECT count(*) FROM notifications WHERE user_id=$1", [c.import.user_id])

    stop_supervised!(__MODULE__)
  end

  defp restore(key, {:ok, value}), do: Application.put_env(:dawarich, key, value)
  defp restore(key, :error), do: Application.delete_env(:dawarich, key)
end
