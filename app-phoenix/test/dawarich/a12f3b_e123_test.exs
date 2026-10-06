defmodule Dawarich.A12f3bE123Test do
  use Dawarich.VisitsCase, async: false
  alias Dawarich.Jobs.{Dispatch, Drain}
  alias Dawarich.Places.DeleteIfOrphanWorker
  alias Dawarich.Visits.RedetectWorker
  @oban __MODULE__.Oban

  defmodule FailureRepo do
    def query!(sql, params \\ [], opts \\ []),
      do: Dawarich.Geocoding.HookRepo.query!(sql, params, opts)

    def query(sql, params \\ [], opts \\ []),
      do: Dawarich.Geocoding.HookRepo.query(sql, params, opts)

    def transaction(fun, opts \\ []), do: Dawarich.ScratchRepo.transaction(fun, opts)
    defdelegate in_transaction?(), to: Dawarich.ScratchRepo
    defdelegate rollback(reason), to: Dawarich.ScratchRepo
    defdelegate insert!(changeset, opts), to: Dawarich.ScratchRepo
  end

  setup do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    start_oban(@oban)
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    :ok
  end

  @tag a12f3b_case: "E123a"
  test "E123 native source shapes reach their terminal effects" do
    for name <- ~w(full_history_redetect full_history_redetect_pl full_history_redetect_partial) do
      reset!(ScratchRepo)
      f = load_visits!(name)
      uid = user_id(f)
      place = stale_place(uid)
      args = args(f)

      if name == "full_history_redetect_partial" do
        [failing, _] = Enum.at(f["months"], f["failing_month"])

        HookRepo.set_hook(fn _sql, params ->
          if match?([_, ^failing, _], params), do: raise("forced month failure")
        end)

        previous = Application.get_env(:dawarich, :jobs_repo)
        Application.put_env(:dawarich, :jobs_repo, __MODULE__.FailureRepo)
        on_exit(fn -> Application.put_env(:dawarich, :jobs_repo, previous) end)
      end

      assert RedetectWorker.perform(job(args)) == :ok
      run_months(args["event_id"])
      HookRepo.clear_hook()
      Application.put_env(:dawarich, :jobs_repo, ScratchRepo)

      assert rows("SELECT kind,title,content FROM notifications WHERE user_id=$1 ORDER BY id", [
               uid
             ]) ==
               Enum.map(f["expected"]["notifications"], &[&1["kind"], &1["title"], &1["content"]])

      assert rows("SELECT visits_redetected_at IS NOT NULL FROM users WHERE id=$1", [uid]) == [
               [name != "full_history_redetect_partial"]
             ]

      assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]

      assert rows("SELECT payload FROM job_outbox WHERE command_type='places.delete_if_orphan'") ==
               [[%{"user_id" => uid, "place_id" => place}]]

      assert Dispatch.run(repo: ScratchRepo, oban: @oban) == %{dispatched: 1}

      [[child]] =
        rows("SELECT args FROM oban.oban_jobs WHERE worker=$1", [inspect(DeleteIfOrphanWorker)])

      assert DeleteIfOrphanWorker.run(ScratchRepo, child) == :ok
      assert rows("SELECT id FROM places WHERE id=$1", [place]) == []
    end
  end

  @tag a12f3b_case: "E123b"
  test "E123 accepted children prevent premature completion" do
    f = load_visits!("full_history_redetect_pl")
    uid = user_id(f)
    place = stale_place(uid)
    args = args(f)
    root = Oban.insert!(@oban, RedetectWorker.new(args))
    assert RedetectWorker.perform(%{root | conf: Oban.config(@oban)}) == :ok
    complete(root.id)
    assert rows("SELECT visits_redetected_at FROM users WHERE id=$1", [uid]) == [[nil]]
    status = Drain.status(ScratchRepo)
    assert status.counts.pending_outbox == 1
    assert status.counts.reverse_pending == 0
    assert status.counts.incomplete_oban >= 1
    assert "pending_outbox" in status.shutdown_reasons
    assert "incomplete_oban" in status.shutdown_reasons

    assert rows(
             "SELECT args->>'event_id',args->>'step' FROM oban.oban_jobs WHERE state IN ('available','scheduled') AND worker=$1",
             [inspect(RedetectWorker)]
           ) == [[args["event_id"], "0"]]

    run_months(args["event_id"])

    assert rows("SELECT visits_redetected_at IS NOT NULL FROM users WHERE id=$1", [uid]) == [
             [true]
           ]

    assert Drain.status(ScratchRepo).counts.pending_outbox == 1
    assert Dispatch.run(repo: ScratchRepo, oban: @oban) == %{dispatched: 1}

    [[id, child]] =
      rows("SELECT id,args FROM oban.oban_jobs WHERE worker=$1", [inspect(DeleteIfOrphanWorker)])

    assert DeleteIfOrphanWorker.run(ScratchRepo, child) == :ok
    complete(id)
    assert rows("SELECT id FROM places WHERE id=$1", [place]) == []

    for [id, child] <-
          rows(
            "SELECT id,args FROM oban.oban_jobs WHERE state NOT IN ('completed','cancelled') AND worker=$1",
            [inspect(Dawarich.Points.VisitMonthsWorker)]
          ) do
      assert Dawarich.Points.VisitMonthsWorker.run(ScratchRepo, child) == :ok
      complete(id)
    end

    status = Drain.status(ScratchRepo)
    assert status.counts.pending_outbox == 0
    assert status.counts.incomplete_oban == 0
    assert status.counts.reverse_pending == 0
  end

  defp args(f),
    do: %{
      "user_id" => user_id(f),
      "event_id" => Ecto.UUID.generate(),
      "time_zone" => f["time_zone"],
      "plan_restricted" => false,
      "step" => "start"
    }

  defp job(args), do: %Oban.Job{args: args, conf: Oban.config(@oban)}

  defp complete(id),
    do: rows("UPDATE oban.oban_jobs SET state='completed',completed_at=now() WHERE id=$1", [id])

  defp run_months(event) do
    case rows(
           "SELECT id,args FROM oban.oban_jobs WHERE worker=$1 AND args->>'event_id'=$2 AND state IN ('available','scheduled') ORDER BY id LIMIT 1",
           [inspect(RedetectWorker), event]
         ) do
      [[id, args]] ->
        assert RedetectWorker.perform(job(args)) == :ok
        complete(id)
        run_months(event)

      [] ->
        :ok
    end
  end

  defp stale_place(uid) do
    [[place]] =
      rows(
        "INSERT INTO places(user_id,name,source,latitude,longitude,created_at,updated_at) VALUES($1,'Suggested place',1,0,0,now(),now()) RETURNING id",
        [uid]
      )

    rows(
      "INSERT INTO visits(user_id,place_id,started_at,ended_at,duration,status,detection_version,confidence,name,created_at,updated_at) VALUES($1,$2,'2020-01-01','2020-01-02',86400,0,3,0.9,'Suggested place',now(),now())",
      [uid, place]
    )

    place
  end
end
