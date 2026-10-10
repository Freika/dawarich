defmodule DawarichWeb.A12f3bI04Test do
  use Dawarich.DataCase, async: false
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.RailsUser
  alias Dawarich.Imports.IntegrationCommands

  setup do
    actor =
      RailsUser.insert!(%{id: 73504, email: "i04@test", settings: %{"timezone" => "Berlin"}})

    for kind <- ~w(immich photoprism),
        do: Ownership.put!(Repo, "command:imports.#{kind}_geodata", :oban)

    for kind <- ~w(imports.airtrail_flights imports.teslamate_sync geocoding.reverse_point),
        do: Ownership.put!(Repo, "command:" <> kind, :oban)

    %{actor: actor}
  end

  @tag a12f3b_case: "I04a"
  test "native backend integration commands preserve all six dispatcher names", %{actor: actor} do
    for provider <- ~w(immich photoprism) do
      assert {:ok, :queued} = enqueue(actor.id, "start_#{provider}_import")
    end

    assert rows("SELECT command_type,payload FROM job_outbox ORDER BY command_type") == [
             ["imports.immich_geodata", %{"user_id" => actor.id, "time_zone" => "Europe/Berlin"}],
             [
               "imports.photoprism_geodata",
               %{"user_id" => actor.id, "time_zone" => "Europe/Berlin"}
             ]
           ]

    for name <-
          ~w(start_airtrail_import start_teslamate_sync start_reverse_geocoding continue_reverse_geocoding),
        do: assert({:ok, :queued} == enqueue(actor.id, name))

    assert rows(
             "SELECT command_type,payload FROM job_outbox WHERE command_type IN ('imports.airtrail_flights','imports.teslamate_sync') ORDER BY command_type"
           ) == [
             ["imports.airtrail_flights", %{"user_id" => actor.id}],
             ["imports.teslamate_sync", %{"user_id" => actor.id}]
           ]

    assert rows("SELECT args FROM oban.oban_jobs ORDER BY id") ==
             Enum.map([true, false], fn force ->
               [%{"user_id" => actor.id, "force" => force, "after_id" => 0, "locale" => "en"}]
             end)

    assert rows("SELECT count(DISTINCT event_id) FROM job_outbox") == [[4]]
    assert commands() == []
    assert rows("SELECT count(*) FROM imports") == [[0]]
    Ownership.put!(Repo, "command:imports.photoprism_geodata", :sidekiq)

    assert {:error, :not_owned} = enqueue(actor.id, "start_photoprism_import")

    assert rows("SELECT count(*) FROM job_outbox") == [[4]]
    assert commands() == []
  end

  @tag a12f3b_case: "I04b"
  test "integration dispatcher failure cannot accept unknown job name", %{actor: actor} do
    Ownership.put!(Repo, "command:imports.teslamate_sync", :oban)

    for job <- [
          "unknown",
          %{"nested" => "start_immich_import"},
          nil
        ] do
      assert {:error, :unknown_job} = enqueue(actor.id, job)
    end

    assert {:error, :not_found} = enqueue(0, "start_immich_import")
    Repo.query!("UPDATE users SET deleted_at=now() WHERE id=$1", [actor.id])
    assert {:error, :not_found} = enqueue(actor.id, "start_immich_import")
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
    assert commands() == []
  end

  defp enqueue(id, name),
    do: IntegrationCommands.enqueue(Repo, id, name, self_hosted: true, locale: "en")
end
