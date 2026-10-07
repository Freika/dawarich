defmodule Dawarich.EnhancedImport.RequestFenceTest do
  use Dawarich.EnhancedImportCase

  alias Dawarich.EnhancedImport.{ExtractGpxWorker, DestroyGpxWorker}
  alias Dawarich.Imports.ManualExtraction
  alias Dawarich.Jobs.{Dispatch, Ownership}

  setup %{storage: storage} do
    fixture = load!("decimal_cast_waypoint")
    Enum.each(fixture["files"], &attach!(storage, &1))
    [import] = fixture["input"]["imports"]

    rows("UPDATE imports SET status=2,additional_data_extraction_status=0 WHERE id=$1", [
      import["id"]
    ])

    Ownership.put!(ScratchRepo, "command:enhanced_import.extract_gpx", :oban)
    Ownership.put!(ScratchRepo, "command:enhanced_import.destroy_gpx", :oban)

    rows(
      "INSERT INTO users(id,email,encrypted_password,created_at,updated_at) VALUES($1,'foreign-fence@example.test','',now(),now())",
      [import["user_id"] + 1]
    )

    start_oban(__MODULE__)
    %{id: import["id"], user: import["user_id"], oban: __MODULE__}
  end

  defp dispatch!(c, action) do
    assert {:ok, :queued} =
             ManualExtraction.enqueue(ScratchRepo, c.user, c.id, action, %{}, %{
               now: DateTime.utc_now(),
               zone: "UTC",
               locale: "en",
               self_hosted?: true
             })

    assert %{dispatched: 1} =
             Dispatch.run(
               repo: ScratchRepo,
               oban: c.oban,
               now: DateTime.add(DateTime.utc_now(), 1)
             )

    [[id]] = rows("SELECT oban_job_id FROM job_outbox ORDER BY created_at DESC LIMIT 1")
    rows("UPDATE oban.oban_jobs SET state='executing',attempt=1 WHERE id=$1", [id])
    ScratchRepo.get!(Oban.Job, id, prefix: "oban")
  end

  defp extract(c, job),
    do: ExtractGpxWorker.run(HookRepo, job, storage: c.storage, lock: [timeout_ms: 0])

  defp effects do
    rows(
      "SELECT kind,payload::text FROM phoenix.rails_commands UNION ALL SELECT worker,args::text FROM oban.oban_jobs WHERE worker IN('Dawarich.Points.ImportCardWorker','Dawarich.Points.UntrackedTracksWorker') ORDER BY 1,2"
    )
  end

  test "changed actor source blob event and attempt refuse every bounded extraction write", c do
    for change <- [:actor, :source, :blob, :event, :attempt, :started_at, :during_download] do
      rows(
        "UPDATE imports SET source=4,additional_data_extraction_status=0,additional_data_extraction='{}' WHERE id=$1",
        [c.id]
      )

      job = dispatch!(c, :extract)

      case change do
        :actor ->
          rows("UPDATE imports SET user_id=$2 WHERE id=$1", [c.id, c.user + 1])

        :source ->
          rows("UPDATE imports SET source=3 WHERE id=$1", [c.id])

        :blob ->
          rows("UPDATE active_storage_attachments SET name='old_file' WHERE record_id=$1", [c.id])

        :event ->
          rows(
            "UPDATE imports SET additional_data_extraction=jsonb_set(additional_data_extraction,'{phoenix_extraction_event}',to_jsonb($2::text)) WHERE id=$1",
            [c.id, Ecto.UUID.generate()]
          )

        :attempt ->
          rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [job.id])

        :started_at ->
          rows(
            "UPDATE imports SET additional_data_extraction=jsonb_set(additional_data_extraction,'{started_at}',to_jsonb($2::text)) WHERE id=$1",
            [c.id, "changed"]
          )

        :during_download ->
          HookRepo.set_hook(fn sql, _ ->
            if sql =~ "SELECT b.key",
              do:
                rows(
                  "UPDATE imports SET additional_data_extraction=jsonb_set(additional_data_extraction,'{phoenix_extraction_event}',to_jsonb($2::text)) WHERE id=$1",
                  [c.id, Ecto.UUID.generate()]
                )

            :ok
          end)
      end

      before = effects()

      assert extract(c, job) in [
               :ok,
               {:cancel, :changed_import},
               {:cancel, :changed_source},
               {:cancel, :stale_attempt}
             ],
             inspect(change)

      assert rows("SELECT count(*) FROM places WHERE import_id=$1", [c.id]) == [[0]],
             inspect(change)

      if change != :during_download, do: assert(effects() == before, inspect(change))
      HookRepo.clear_hook()
      rows("UPDATE imports SET user_id=$2 WHERE id=$1", [c.id, c.user])
      rows("UPDATE active_storage_attachments SET name='file' WHERE record_id=$1", [c.id])
    end
  end

  test "the same completed extraction event does not execute its effects twice through dispatch",
       c do
    job = dispatch!(c, :extract)
    assert :ok = extract(c, job)
    effects = effects()
    assert length(effects) == 3
    assert :ok = extract(c, job)
    assert effects() == effects
    assert rows("SELECT count(*) FROM places WHERE import_id=$1", [c.id]) == [[1]]
  end

  test "a retried old removal cannot delete a newer extraction through dispatch", c do
    assert :ok = extract(c, dispatch!(c, :extract))
    old = dispatch!(c, :remove)
    assert :ok = DestroyGpxWorker.run(ScratchRepo, old)
    assert :ok = extract(c, dispatch!(c, :extract))
    effects = effects()
    rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [old.id])
    assert :ok = DestroyGpxWorker.run(ScratchRepo, %{old | attempt: 2})
    assert rows("SELECT count(*) FROM places WHERE import_id=$1", [c.id]) == [[1]]
    assert {3, _, _} = import_state(c.id)
    assert effects() == effects
  end
end
