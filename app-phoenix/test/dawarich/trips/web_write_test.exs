defmodule Dawarich.Trips.WebWriteTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.{RailsUser, TripsSeeds}
  alias Dawarich.Trips.WebWrite

  @now ~U[2026-10-03 10:00:00.000000Z]
  @effects "test/fixtures/trips/remaining/effects.json"
           |> File.read!()
           |> Jason.decode!()
           |> Map.fetch!("effects")
  @responses "test/fixtures/trips/remaining/responses.json"
             |> File.read!()
             |> Jason.decode!()
             |> Map.fetch!("responses")

  defmodule FailedAfterOutbox do
    defdelegate transaction(fun), to: Dawarich.Repo
    defdelegate query(sql, params), to: Dawarich.Repo

    def query!(sql, params, opts \\ []) do
      result = Dawarich.Repo.query!(sql, params, opts)

      if String.contains?(sql, "INSERT INTO public.job_outbox"),
        do:
          Dawarich.Repo.query!("UPDATE trips SET user_id = NULL WHERE id = $1", [
            Enum.at(params, 2)
          ])

      result
    end
  end

  defp naive(raw), do: raw |> DateTime.from_iso8601() |> elem(1) |> DateTime.to_naive()

  defp seed(entry) do
    actor = entry["before"]["actor"]

    user =
      RailsUser.insert!(%{
        id: actor["id"],
        email: "a8-write-#{actor["id"]}@example.invalid",
        settings: actor["settings"]
      })

    for trip <- entry["before"]["trips"] do
      if trip["user_id"] != user.id and
           Repo.query!("SELECT id FROM users WHERE id = $1", [trip["user_id"]]).rows == [],
         do:
           RailsUser.insert!(%{
             id: trip["user_id"],
             email: "a8-owner-#{trip["user_id"]}@example.invalid"
           })

      TripsSeeds.trip!(%{
        id: trip["id"],
        user_id: trip["user_id"],
        name: trip["name"],
        demo: trip["demo"],
        started_at: naive(trip["started_at"]),
        ended_at: naive(trip["ended_at"]),
        created_at: naive(trip["created_at"]),
        updated_at: naive(trip["updated_at"])
      })
    end

    for rich <- entry["before"]["action_text_rich_texts"],
        do:
          Repo.insert_all("action_text_rich_texts", [
            %{
              id: rich["id"],
              record_id: rich["record_id"],
              record_type: "Trip",
              name: "description",
              body: rich["body"],
              created_at: naive(rich["created_at"]),
              updated_at: naive(rich["updated_at"])
            }
          ])

    user
  end

  defp snapshot(id) do
    [
      Repo.query!(
        "SELECT name, demo, started_at, ended_at, created_at, updated_at FROM trips WHERE id = $1",
        [id]
      ).rows,
      Repo.query!(
        "SELECT body, created_at, updated_at FROM action_text_rich_texts WHERE record_type = 'Trip' AND record_id = $1",
        [id]
      ).rows,
      Repo.query!("SELECT payload FROM job_outbox WHERE aggregate_id = $1", [id]).rows
    ]
  end

  defp totals(user),
    do:
      Repo.query!(
        "SELECT (SELECT count(*) FROM trips WHERE user_id = $1), (SELECT count(*) FROM job_outbox), (SELECT count(*) FROM phoenix.rails_commands)",
        [user.id]
      ).rows

  test "trip saves preserve callbacks demo and rollback phases" do
    for entry <- @effects,
        entry["request"]["fault"] == nil,
        entry["request"]["method"] in ~w(POST PATCH),
        Map.has_key?(entry["request"]["params"], "trip") do
      user = seed(entry)

      Ownership.put!(
        Repo,
        "command:trips.calculate",
        String.to_existing_atom(entry["request"]["owner"])
      )

      action = if entry["before"]["trips"] == [], do: :create, else: :update
      old = List.first(entry["before"]["trips"])
      id = old && old["id"]
      before = snapshot(id || 0)
      totals_before = totals(user)
      response = Enum.find(@responses, &(&1["name"] == entry["name"]))
      attrs = entry["request"]["params"]["trip"]
      result = WebWrite.run(Repo, action, user, id, attrs, %{now: @now, locale: "en"})
      calculates = action == :create or (Map.has_key?(attrs, "started_at") and not old["demo"])

      cond do
        old && old["user_id"] != user.id ->
          assert {:error, :not_found} = result
          assert snapshot(id) == before
          assert totals(user) == totals_before

        response["status"] == 422 or response["error"] != nil ->
          assert {:invalid, errors, _} = result

          if response["status"] == 422,
            do: assert(Enum.map(errors, &elem(&1, 1)) == Enum.drop(response["errors"], 1))

          assert snapshot(id || 0) == before
          assert totals(user) == totals_before

        calculates and entry["request"]["owner"] == "sidekiq" ->
          assert {:replay, _} = result
          assert snapshot(id || 0) == before
          assert totals(user) == totals_before

        true ->
          assert {:ok, row} = result
          [expected] = entry["after"]["trips"]
          assert {row.name, row.demo} == {expected["name"], expected["demo"]}, entry["name"]

          for field <- ~w(started_at ended_at created_at updated_at)a,
              do:
                assert(
                  NaiveDateTime.compare(row[field], naive(expected[Atom.to_string(field)])) ==
                    :eq,
                  entry["name"] <> " #{field}"
                )

          [_, rich, outbox] = snapshot(row.id)

          assert rich ==
                   Enum.map(
                     entry["after"]["action_text_rich_texts"],
                     &[&1["body"], naive(&1["created_at"]), naive(&1["updated_at"])]
                   ),
                 entry["name"]

          assert length(outbox) == length(entry["queue"]["outbox"]), entry["name"]
          if calculates, do: assert(outbox == [[%{"trip_id" => row.id, "distance_unit" => "km"}]])

          if action == :create do
            Repo.query!("DELETE FROM job_outbox WHERE aggregate_id = $1", [row.id])
            Repo.query!("DELETE FROM trips WHERE id = $1", [row.id])
          end
      end

      assert commands() == []
    end

    failure = Enum.find(@effects, &(&1["name"] == "update_sql_failure_oban"))
    user = seed(failure)
    Ownership.put!(Repo, "command:trips.calculate", :oban)
    [trip] = failure["before"]["trips"]
    before = snapshot(trip["id"])

    assert_raise Postgrex.Error, fn ->
      WebWrite.run(
        FailedAfterOutbox,
        :update,
        user,
        trip["id"],
        failure["request"]["params"]["trip"],
        %{now: @now}
      )
    end

    assert snapshot(trip["id"]) == before
    assert failure["before"]["trips"] == failure["after"]["trips"]
    assert failure["queue"]["outbox"] == []

    assert_raise Postgrex.Error, fn ->
      WebWrite.run(
        FailedAfterOutbox,
        :create,
        user,
        nil,
        %{
          "name" => "Auwald",
          "started_at" => "2026-10-03T09:00",
          "ended_at" => "2026-10-04T09:00"
        },
        %{now: @now}
      )
    end

    assert Repo.query!("SELECT count(*) FROM trips WHERE user_id = $1", [user.id]).rows == [[1]]
    assert commands() == []

    for unit <- ~w(mi m ft yd) do
      actor = %{user | settings: Map.put(user.settings, "maps", %{"distance_unit" => unit})}

      assert {:ok, created} =
               WebWrite.run(
                 Repo,
                 :create,
                 actor,
                 nil,
                 %{
                   "name" => "Auwald",
                   "started_at" => "2026-10-03T09:00",
                   "ended_at" => "2026-10-04T09:00"
                 },
                 %{now: @now}
               )

      assert Repo.query!("SELECT payload FROM job_outbox WHERE aggregate_id = $1", [created.id]).rows ==
               [[%{"trip_id" => created.id, "distance_unit" => unit}]]
    end

    entry = Enum.find(@effects, &(&1["name"] == "update_name_ordinary_oban"))
    actor = %{id: entry["before"]["actor"]["id"], settings: entry["before"]["actor"]["settings"]}
    [rich] = entry["before"]["action_text_rich_texts"]

    Repo.insert_all("active_storage_blobs", [
      %{
        id: 896_990,
        key: "a8-rest-synthetic-embed",
        filename: "synthetic.txt",
        service_name: "local",
        byte_size: 1,
        checksum: "SYNTHETIC",
        created_at: DateTime.to_naive(@now)
      }
    ])

    Repo.insert_all("active_storage_attachments", [
      %{
        record_type: "ActionText::RichText",
        record_id: rich["id"],
        name: "embeds",
        blob_id: 896_990,
        created_at: DateTime.to_naive(@now)
      }
    ])

    before = snapshot(rich["record_id"])

    assert {:ok, _} =
             WebWrite.run(
               Repo,
               :update,
               actor,
               rich["record_id"],
               %{"name" => before |> hd() |> hd() |> hd()},
               %{now: @now}
             )

    assert snapshot(rich["record_id"]) == before
  end
end
