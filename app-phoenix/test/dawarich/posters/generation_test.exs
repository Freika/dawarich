defmodule Dawarich.Posters.GenerationTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Posters.Generation
  alias Dawarich.Jobs.{Ownership, Processed}

  setup do
    root = Path.join(System.tmp_dir!(), "a9-publish-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    Ownership.put!(ScratchRepo, "command:posters.create", :oban)
    saved_zone = System.get_env("TIME_ZONE")

    on_exit(fn ->
      if saved_zone,
        do: System.put_env("TIME_ZONE", saved_zone),
        else: System.delete_env("TIME_ZONE")
    end)

    %{root: root, storage: %{root: root, service: "local"}}
  end

  @tag mutation: "poster-job-zone"
  test "poster generation selects Rails no offset date only windows and UTC subtitles", c do
    for name <- ~w(no_offset date_only explicit_offset configured_zone),
        do: assert_time_generation(name, c)
  end

  @tag mutation: "poster-dst"
  test "poster generation preserves Rails spring gap and autumn daylight selection", c do
    for name <- ~w(dst_spring dst_fall), do: assert_time_generation(name, c)
  end

  @tag mutation: "poster-missing-time"
  test "poster generation preserves Rails missing blank and zero epoch failure outcomes", c do
    for name <- ~w(missing blank whitespace blank_epoch_points blank_tracks),
        do: assert_time_generation(name, c)
  end

  @tag mutation: "poster-epoch-range"
  test "poster generation accepts Rails track windows beyond signed 32 bit epochs", c do
    for name <- ~w(beyond_2038 beyond_2038_points), do: assert_time_generation(name, c)
  end

  @tag mutation: "poster-grammar-precision"
  test "poster generation preserves Rails human date grammar and fractional track bounds", c do
    for name <- ~w(human_date fractional_tracks), do: assert_time_generation(name, c)
  end

  defp assert_time_generation(name, c) do
    state = seed("timestamps/" <> name)
    System.put_env("TIME_ZONE", state["time_zone"])
    rows("UPDATE users SET settings=$1", [%{"timezone" => "UTC", "locale" => "en"}])
    id = state["before"]["id"]
    event = Ecto.UUID.generate()

    assert :ok =
             Generation.run(id, state["actor_id"], event, state["locale"],
               repo: ScratchRepo,
               storage: c.storage,
               render_options: [
                 command: [
                   "ruby",
                   Path.expand("../spec/fixtures/scripts/fake_poster_renderer.rb")
                 ]
               ]
             )

    assert rows("SELECT status,settings FROM posters WHERE id=$1", [id]) == [
             [state["after"]["status"], state["after"]["settings"]]
           ],
           name

    assert Processed.done?(ScratchRepo, event)

    for {key, expected} <- state["parsed_times"], is_binary(expected) do
      parsed =
        state["before"]["settings"][key]
        |> Dawarich.Posters.Time.parse()
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.to_iso8601()

      assert {name, key, parsed} == {name, key, expected}
    end

    attachments =
      rows(
        "SELECT a.name,b.key FROM active_storage_attachments a JOIN active_storage_blobs b ON b.id=a.blob_id WHERE a.record_type='Poster' AND a.record_id=$1 ORDER BY a.name",
        [id]
      )

    assert Enum.map(attachments, &hd/1) == Enum.map(state["attachments"], & &1["name"]), name

    for ["image", key] <- attachments do
      job = c.storage |> Dawarich.Storage.get!(key) |> Jason.decode!()
      assert Map.drop(job, ["output"]) == Map.drop(state["render_job"], ["output"]), name
    end
  end

  @tag mutation: "completed"
  test "generation preserves completed no op and localizes absent outside failed states", c do
    for name <-
          ~w(already_completed_without_pair absent_points outside_frame null_lonlat unknown_theme points_gap_boundaries overlapping_tracks_theme_basename) do
      state = seed(name)
      event = Ecto.UUID.generate()

      renderer =
        if name == "unknown_theme",
          do: fn _, _, _ -> raise "unknown theme" end,
          else: fn _, _, _ -> %{png: "synthetic png", pdf: "synthetic pdf"} end

      renderer =
        if name == "already_completed_without_pair",
          do: fn _, _, _ -> flunk("completed poster rendered again") end,
          else: renderer

      assert :ok =
               Generation.run(state["before"]["id"], state["actor_id"], event, state["locale"],
                 repo: ScratchRepo,
                 storage: c.storage,
                 renderer: renderer
               )

      assert [[status, settings]] =
               rows("SELECT status,settings FROM posters WHERE id=$1", [state["before"]["id"]])

      assert status == state["after"]["status"]
      assert settings == state["after"]["settings"]
      assert Processed.done?(ScratchRepo, event)

      assert rows(
               "SELECT count(*) FROM active_storage_attachments WHERE record_type='Poster' AND record_id=$1",
               [state["before"]["id"]]
             ) == [[length(state["attachments"])]]
    end

    assert_raise Ecto.NoResultsError, fn ->
      Generation.run(96999, 97101, Ecto.UUID.generate(), "en",
        repo: ScratchRepo,
        storage: c.storage
      )
    end
  end

  @tag mutation: "fence"
  test "deletion or lost lease discards all uncommitted objects and never recreates poster", c do
    for mode <- [:delete, :lease] do
      state = seed("points_gap_boundaries")
      id = state["before"]["id"]
      event = Ecto.UUID.generate()

      renderer = fn _, _, _ ->
        refute ScratchRepo.in_transaction?()

        case mode do
          :delete ->
            rows("DELETE FROM posters WHERE id=$1", [id])

          :lease ->
            rows("UPDATE phoenix.leases SET holder='new-holder' WHERE name=$1", ["posters:#{id}"])
        end

        %{png: "synthetic png", pdf: "synthetic pdf"}
      end

      assert :lost =
               Generation.run(id, state["actor_id"], event, state["locale"],
                 repo: ScratchRepo,
                 storage: c.storage,
                 renderer: renderer
               )

      assert rows("SELECT id FROM active_storage_blobs") == []
      assert rows("SELECT id FROM active_storage_attachments") == []
      assert Path.wildcard(c.root <> "/**/*") |> Enum.filter(&File.regular?/1) == []
      if mode == :delete, do: assert(rows("SELECT id FROM posters WHERE id=$1", [id]) == [])
      if mode == :lease, do: assert(rows("SELECT status FROM posters WHERE id=$1", [id]) == [[1]])
      refute Processed.done?(ScratchRepo, event)
      rows("DELETE FROM phoenix.leases")
    end
  end

  defp seed(name) do
    state = File.read!("test/fixtures/posters/" <> name <> ".json") |> Jason.decode!()

    Dawarich.FixtureCleanup.delete!(
      ScratchRepo,
      ~w(public.posters public.points public.tracks public.users)
    )

    rows("DELETE FROM phoenix.processed_commands")

    rows(
      "INSERT INTO users(id,email,created_at,updated_at) VALUES($1,'a9-generation@dawarich.test',now(),now())",
      [state["actor_id"]]
    )

    insert("posters", state["before"])
    for row <- state["points"], do: insert("points", row)
    for row <- state["tracks"], do: insert("tracks", row)
    state
  end

  defp insert(table, row),
    do:
      rows(
        "INSERT INTO #{table} SELECT * FROM json_populate_record(NULL::#{table},$1::text::json)",
        [Jason.encode!(row)]
      )
end
