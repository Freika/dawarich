defmodule Dawarich.Posters.CreateWorkerTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Posters.{CreateWorker, Generation}
  alias Dawarich.Jobs.{Dispatch, Ownership, Registry}

  setup do
    root = Path.join(System.tmp_dir!(), "a9-worker-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "public"))
    File.cp_r!(Path.expand("../public/poster_themes"), Path.join(root, "public/poster_themes"))
    command = System.get_env("POSTER_RENDERER_CMD")
    backend = System.get_env("STORAGE_BACKEND")
    old_root = Application.get_env(:dawarich, :rails_root)
    old_repo = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :rails_root, root)
    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)
    System.delete_env("STORAGE_BACKEND")

    System.put_env(
      "POSTER_RENDERER_CMD",
      "ruby " <> Path.expand("../spec/fixtures/scripts/fake_poster_renderer.rb")
    )

    Ownership.put!(ScratchRepo, "command:posters.create", :oban)
    start_oban(__MODULE__)

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_root, old_root)
      Application.put_env(:dawarich, :jobs_repo, old_repo)

      if command,
        do: System.put_env("POSTER_RENDERER_CMD", command),
        else: System.delete_env("POSTER_RENDERER_CMD")

      if backend,
        do: System.put_env("STORAGE_BACKEND", backend),
        else: System.delete_env("STORAGE_BACKEND")

      File.rm_rf!(root)
    end)

    %{root: root}
  end

  @tag mutation: "decode"
  test "decoder accepts only version one poster user locale payload" do
    payload = %{"poster_id" => 1, "user_id" => 2, "locale" => "de"}
    assert {:ok, ^payload} = CreateWorker.args_from_command(1, payload)
    assert {:error, "unsupported_version"} = CreateWorker.args_from_command(2, payload)

    for bad <- [
          Map.put(payload, "settings", %{}),
          Map.put(payload, "poster_id", "1"),
          Map.put(payload, "user_id", 0),
          Map.put(payload, "locale", "xx"),
          Map.delete(payload, "locale")
        ] do
      assert {:error, "invalid_payload"} = CreateWorker.args_from_command(1, bad)
    end
  end

  @tag mutation: "registry"
  test "registry dispatches posters create on posters queue with two attempts", c do
    state = seed("points_gap_boundaries")
    assert {:ok, CreateWorker} = Registry.command("posters.create")
    assert Enum.find(Registry.entries(), &(&1.key == "command:posters.create")).claimable == false
    assert File.read!("config/runtime.exs") =~ "posters: 1"

    assert Dawarich.RailsJobOwners.owners()["Posters::CreateJob"] ==
             {:oban, ["command:posters.create"]}

    event = enqueue(state)

    assert [["posters", 2, "available", %{"poster_id" => id}]] =
             rows("SELECT queue,max_attempts,state,args FROM oban.oban_jobs")

    assert id == state["before"]["id"]
    assert %{success: 1, failure: 0} = Oban.drain_queue(__MODULE__, queue: :posters)
    assert rows("SELECT status FROM posters WHERE id=$1", [id]) == [[2]]

    assert rows("SELECT name FROM active_storage_attachments WHERE record_id=$1 ORDER BY name", [
             id
           ]) == [["image"], ["print_pdf"]]

    assert rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id") == []

    assert rows(
             "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Posters.ProgressWorker' ORDER BY id"
           )
           |> Enum.map(fn [args] -> Map.drop(args, ["event_id"]) end) ==
             List.duplicate(payload(state), 3)

    saved = Application.get_env(:dawarich, :cable)
    Application.put_env(:dawarich, :cable, transport: :pg)
    on_exit(fn -> Application.put_env(:dawarich, :cable, saved) end)
    assert %{success: 3, failure: 0} = Oban.drain_queue(__MODULE__, queue: :posters)
    assert rows("SELECT count(*) FROM phoenix.cable_events") == [[3]]

    assert Dawarich.Jobs.Processed.done?(ScratchRepo, event)
    assert length(Path.wildcard(c.root <> "/storage/??/??/*")) == 2
    args = Map.put(payload(state), "event_id", Ecto.UUID.generate())
    assert {:ok, job} = Oban.insert(__MODULE__, CreateWorker.new(args))
    assert {:ok, same} = Oban.insert(__MODULE__, CreateWorker.new(args))
    assert same.conflict? and same.id == job.id
  end

  @tag mutation: "rehome"
  test "old owner and rehome fence publication while Rails fallback stays available", c do
    state = seed("points_gap_boundaries")
    Ownership.put!(ScratchRepo, "command:posters.create", :sidekiq)
    args = Map.put(payload(state), "event_id", Ecto.UUID.generate())
    assert {:cancel, _} = CreateWorker.perform(%Oban.Job{args: args})
    assert rows("SELECT status FROM posters WHERE id=$1", [state["before"]["id"]]) == [[0]]

    for mode <- [:sidekiq, :roundtrip] do
      Ownership.put!(ScratchRepo, "command:posters.create", :oban)

      renderer = fn _, _, _ ->
        Ownership.put!(ScratchRepo, "command:posters.create", :sidekiq)
        if mode == :roundtrip, do: Ownership.put!(ScratchRepo, "command:posters.create", :oban)
        %{png: "synthetic png", pdf: "synthetic pdf"}
      end

      assert :lost =
               Generation.run(
                 state["before"]["id"],
                 state["actor_id"],
                 Ecto.UUID.generate(),
                 "en",
                 repo: ScratchRepo,
                 renderer: renderer,
                 storage: %{root: c.root, service: "local"}
               )

      assert rows("SELECT id FROM active_storage_blobs") == []
      assert Path.wildcard(c.root <> "/??/??/*") == []
    end

    assert File.read!("../app/services/posters/creation_command.rb") =~ "sidekiq(payload)"
  end

  @tag mutation: "result"
  test "caught business failure completes Oban with failed poster while escaped job lookup uses retry contract" do
    state = seed("absent_points")
    enqueue(state)
    assert %{success: 1, failure: 0} = Oban.drain_queue(__MODULE__, queue: :posters)
    assert rows("SELECT status FROM posters WHERE id=$1", [state["before"]["id"]]) == [[3]]

    assert rows(
             "SELECT state,attempt FROM oban.oban_jobs WHERE worker='Dawarich.Posters.CreateWorker'"
           ) == [["completed", 1]]

    saved = Application.get_env(:dawarich, :cable)
    Application.put_env(:dawarich, :cable, transport: :pg)
    on_exit(fn -> Application.put_env(:dawarich, :cable, saved) end)
    assert %{success: 2, failure: 0} = Oban.drain_queue(__MODULE__, queue: :posters)
    assert rows("SELECT count(*) FROM phoenix.cable_events") == [[2]]

    outbox!(
      command_type: "posters.create",
      payload: Map.put(payload(state), "poster_id", 99_999_999)
    )

    assert %{dispatched: 1} =
             Dispatch.run(
               now: Dawarich.JobsCase.db_now(ScratchRepo),
               repo: ScratchRepo,
               oban: __MODULE__
             )

    assert %{success: 0, failure: 1} = Oban.drain_queue(__MODULE__, queue: :posters)

    assert [["retryable", 1, 2, errors]] =
             rows(
               "SELECT state,attempt,max_attempts,errors FROM oban.oban_jobs WHERE state <> 'completed'"
             )

    assert inspect(errors) =~ "Ecto.NoResultsError"
  end

  defp enqueue(state) do
    event = outbox!(command_type: "posters.create", payload: payload(state))

    assert %{dispatched: 1} =
             Dispatch.run(
               now: Dawarich.JobsCase.db_now(ScratchRepo),
               repo: ScratchRepo,
               oban: __MODULE__
             )

    event
  end

  defp payload(state),
    do: %{
      "poster_id" => state["before"]["id"],
      "user_id" => state["actor_id"],
      "locale" => state["locale"]
    }

  defp seed(name) do
    state = File.read!("test/fixtures/posters/" <> name <> ".json") |> Jason.decode!()

    rows(
      "INSERT INTO users(id,email,created_at,updated_at) VALUES($1,'a9-worker@dawarich.test',now(),now())",
      [state["actor_id"]]
    )

    for {table, data} <- [
          {"posters", [state["before"]]},
          {"points", state["points"]},
          {"tracks", state["tracks"]}
        ],
        row <- data do
      rows(
        "INSERT INTO #{table} SELECT * FROM json_populate_record(NULL::#{table},$1::text::json)",
        [Jason.encode!(row)]
      )
    end

    state
  end
end
