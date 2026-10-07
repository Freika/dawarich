defmodule Dawarich.Imports.PartialZipDispositionTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.ProcessWorker
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

  for mode <- ["on", "off"] do
    test "partial ZIP build retains an executor for accepted children before parent failure in #{mode}",
         c do
      System.put_env("DAWARICH_RAILS", unquote(mode))

      c =
        Map.merge(
          c,
          NormalFormats.whole!("zip_extractor_later_child_failure", ScratchRepo, c.root)
        )

      for entry <- Registry.entries(), do: Ownership.put!(ScratchRepo, entry.key, :oban)
      start_oban(__MODULE__)
      assert {:snooze, 5} = ProcessWorker.perform(c.job)
      assert [[1]] == rows("SELECT status FROM imports WHERE id=$1", [c.import.id])
      refute Processed.done?(ScratchRepo, c.job.args["event_id"])
      assert [] == rows("SELECT id FROM notifications")

      assert [[child, "queued"]] =
               rows(
                 "SELECT child_id,phase FROM phoenix.import_archive_children WHERE parent_id=$1 AND child_id IS NOT NULL",
                 [c.import.id]
               )

      if unquote(mode) == "on",
        do:
          assert(
            %{dispatched: 1} = Dawarich.Jobs.Dispatch.run(repo: ScratchRepo, oban: __MODULE__)
          )

      assert [[id, args, worker]] =
               rows(
                 "UPDATE oban.oban_jobs SET state='executing',attempt=1 WHERE args->>'import_id'=$1 RETURNING id,args,worker",
                 [to_string(child)]
               )

      assert :ok =
               ProcessWorker.perform(%Oban.Job{id: id, args: args, worker: worker, attempt: 1})

      assert [[status]] = rows("SELECT status FROM imports WHERE id=$1", [child])
      assert status in [2, 3]
      assert :ok = ProcessWorker.perform(c.job)

      assert [[3, error]] =
               rows("SELECT status,error_message FROM imports WHERE id=$1", [c.import.id])

      assert error == c.expected["parent"]["error_message"]

      assert [[1]] ==
               rows("SELECT count(*) FROM notifications WHERE kind=2 AND user_id=$1", [
                 c.import.user_id
               ])

      assert Processed.done?(ScratchRepo, c.job.args["event_id"])
      assert :ok = ProcessWorker.perform(c.job)

      assert [[1]] ==
               rows("SELECT count(*) FROM notifications WHERE kind=2 AND user_id=$1", [
                 c.import.user_id
               ])
    end
  end

  defp restore(key, {:ok, value}), do: Application.put_env(:dawarich, key, value)
  defp restore(key, :error), do: Application.delete_env(:dawarich, key)
end
