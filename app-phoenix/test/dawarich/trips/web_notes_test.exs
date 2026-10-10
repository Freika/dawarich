defmodule Dawarich.Trips.WebNotesTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db
  alias Dawarich.Test.RailsUser
  alias Dawarich.Trips.WebNotes
  @now ~U[2026-10-03 10:00:00.000000Z]
  @effects File.read!("test/fixtures/trips/remaining/effects.json")
           |> Jason.decode!()
           |> Map.fetch!("effects")
  @responses File.read!("test/fixtures/trips/remaining/responses.json")
             |> Jason.decode!()
             |> Map.fetch!("responses")

  defmodule ExternalInsert do
    defdelegate transaction(fun), to: Dawarich.ScratchRepo
    defdelegate query(sql, params), to: Dawarich.ScratchRepo
    defdelegate rollback(reason), to: Dawarich.ScratchRepo

    def query!(sql, params, opts \\ []) do
      if String.starts_with?(sql, "INSERT INTO notes") do
        Task.async(fn ->
          Dawarich.ScratchRepo.query!(sql, List.replace_at(params, 1, "External writer"), opts)
        end)
        |> Task.await()
      end

      Dawarich.ScratchRepo.query!(sql, params, opts)
    end
  end

  defp seed(entry) do
    actor = entry["before"]["actor"]

    user =
      RailsUser.insert!(
        %{
          id: actor["id"],
          email: "a8-webnote-#{actor["id"]}@example.invalid",
          settings: actor["settings"]
        },
        ScratchRepo
      )

    for trip <- entry["before"]["trips"] do
      if trip["user_id"] != user.id,
        do:
          RailsUser.insert!(
            %{id: trip["user_id"], email: "foreignnote-#{trip["user_id"]}@example.invalid"},
            ScratchRepo
          )

      row = Map.drop(trip, ~w(path))

      rows("INSERT INTO trips SELECT * FROM json_populate_record(NULL::trips, $1::text::json)", [
        Jason.encode!(row)
      ])
    end

    for note <- entry["before"]["notes"],
        do:
          rows(
            "INSERT INTO notes SELECT * FROM json_populate_record(NULL::notes, $1::text::json)",
            [Jason.encode!(note)]
          )

    user
  end

  defp saved(id),
    do:
      rows(
        "SELECT id, body, noted_at, user_id, created_at, updated_at FROM notes WHERE attachable_type = 'Trip' AND attachable_id = $1 ORDER BY id",
        [id]
      )

  defp naive(raw), do: raw |> DateTime.from_iso8601() |> elem(1) |> DateTime.to_naive()

  @tag a12f3a_t08_edges: true
  test "T08: note dates retain Ruby ordinal and commercial week casting" do
    user =
      RailsUser.insert!(
        %{id: 989_201, email: "trip-note-dates@example.test", settings: %{}},
        ScratchRepo
      )

    rows(
      "INSERT INTO trips(id,user_id,name,started_at,ended_at,created_at,updated_at) VALUES(989202,$1,'Auwald','2026-10-02','2026-10-04',$2,$2)",
      [user.id, DateTime.to_naive(@now)]
    )

    for raw <- ~w(2026-W40-6 2026-276 20261003 2026W406) do
      assert {:ok, %{date: ~D[2026-10-03], note: note}} =
               WebNotes.run(
                 ScratchRepo,
                 :create,
                 user,
                 989_202,
                 nil,
                 %{"date" => raw, "body" => raw},
                 %{now: @now}
               )

      assert note.noted_at == ~N[2026-10-03 12:00:00.000000]
      assert length(saved(989_202)) == 1
    end

    before = saved(989_202)

    for raw <- ~w(2026-W54-6 2026-367) do
      assert {:invalid_date} =
               WebNotes.run(
                 ScratchRepo,
                 :create,
                 user,
                 989_202,
                 nil,
                 %{"date" => raw, "body" => raw},
                 %{now: @now}
               )

      assert saved(989_202) == before
    end

    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  @tag a12f3a_t09: true
  test "nested notes preserve scope noon upsert and unique-date race" do
    for entry <- @effects,
        entry["request"]["method"] in ~w(POST PATCH DELETE),
        String.starts_with?(entry["name"], "note_") or
          entry["name"] in ~w(foreign_note_update foreign_note_destroy) do
      user = seed(entry)
      path = String.split(entry["request"]["path"], "/", trim: true)
      trip_id = path |> Enum.at(1) |> String.to_integer()
      note_id = if length(path) == 4, do: path |> Enum.at(3) |> String.to_integer()

      action =
        case entry["request"]["method"] do
          "POST" -> :create
          "PATCH" -> :update
          "DELETE" -> :destroy
        end

      attrs = entry["request"]["params"]["note"] || %{}
      before = saved(trip_id)
      response = Enum.find(@responses, &(&1["name"] == entry["name"]))
      result = WebNotes.run(ScratchRepo, action, user, trip_id, note_id, attrs, %{now: @now})

      cond do
        String.starts_with?(entry["name"], "foreign_") ->
          assert {:error, :not_found} = result
          assert saved(trip_id) == before

        entry["name"] =~ "bad-date" ->
          assert {:invalid_date} = result
          assert saved(trip_id) == before

        response["errors"] != [] or response["flash"]["alert"] != nil ->
          assert {:invalid, errors, note} = result

          expected =
            if response["errors"] != [],
              do: response["errors"],
              else: [response["flash"]["alert"]]

          assert errors == expected, entry["name"]
          assert note.body == attrs["body"]
          assert saved(trip_id) == before

        action == :destroy ->
          assert {:ok, %{date: ~D[2026-10-03]}} = result
          assert saved(trip_id) == []

        true ->
          assert {:ok, %{note: note}} = result
          [expected] = entry["after"]["notes"]

          assert {note.body, note.noted_at, note.user_id} ==
                   {expected["body"], naive(expected["noted_at"]), expected["user_id"]}

          assert note.created_at == naive(expected["created_at"])
          assert note.updated_at == naive(expected["updated_at"])
          assert length(saved(trip_id)) == 1
      end
    end

    user =
      RailsUser.insert!(
        %{
          id: 899_901,
          email: "a8-noterace@example.invalid",
          settings: %{"timezone" => "Europe/Berlin"}
        },
        ScratchRepo
      )

    rows(
      "INSERT INTO trips (id,user_id,name,started_at,ended_at,created_at,updated_at) VALUES (899902,$1,'Auwald','2026-10-02 22:30','2026-10-04 01:00',$2,$2)",
      [user.id, DateTime.to_naive(@now)]
    )

    attrs = %{"date" => "2026-10-03", "body" => "First"}

    tasks =
      for body <- ~w(First Second),
          do:
            Task.async(fn ->
              WebNotes.run(ScratchRepo, :create, user, 899_902, nil, %{attrs | "body" => body}, %{
                now: @now
              })
            end)

    results = Enum.map(tasks, &Task.await/1)
    assert Enum.all?(results, &match?({:ok, _}, &1))
    assert [[_, body, ~N[2026-10-03 12:00:00.000000], _, _, _]] = saved(899_902)
    assert body in ~w(First Second)

    assert {:ok, %{note: %{body: "\nAuwald"}}} =
             WebNotes.run(
               ScratchRepo,
               :create,
               user,
               899_902,
               nil,
               %{attrs | "body" => "\nAuwald"},
               %{now: @now}
             )

    assert length(saved(899_902)) == 1

    assert {:ok, _} =
             WebNotes.run(
               ScratchRepo,
               :create,
               user,
               899_902,
               nil,
               %{attrs | "date" => "Oct 3 2026"},
               %{now: @now}
             )

    assert {:error, :not_found} =
             WebNotes.run(ScratchRepo, :create, %{user | id: user.id + 1}, 899_902, nil, attrs, %{
               now: @now
             })

    rows(
      "INSERT INTO trips (id,user_id,name,started_at,ended_at,created_at,updated_at) VALUES (899903,$1,'Auwald','2026-10-02 22:30','2026-10-04 01:00',$2,$2)",
      [user.id, DateTime.to_naive(@now)]
    )

    assert {:ok, %{note: %{body: "First"}}} =
             WebNotes.run(ExternalInsert, :create, user, 899_903, nil, attrs, %{now: @now})

    assert [[_, "First", _, _, _, _]] = saved(899_903)

    literal =
      "<action-text-attachment sgid=\"synthetic-invalid\"></action-text-attachment><script>text</script>"

    assert {:ok, %{note: note}} =
             WebNotes.run(
               ScratchRepo,
               :create,
               user,
               899_903,
               nil,
               %{attrs | "body" => literal},
               %{now: @now}
             )

    assert note.body == literal

    assert rows("SELECT count(*) FROM active_storage_attachments WHERE record_type='Note'") == [
             [0]
           ]

    assert {:ok, %{note: updated}} =
             WebNotes.run(
               ScratchRepo,
               :update,
               user,
               899_903,
               note.id,
               %{"body" => literal <> " next"},
               %{now: @now}
             )

    assert updated.body == literal <> " next"

    assert {:ok, _} =
             WebNotes.run(ScratchRepo, :destroy, user, 899_903, note.id, %{}, %{now: @now})

    assert saved(899_903) == []
    assert rows("SELECT 1") == [[1]]
  end
end
