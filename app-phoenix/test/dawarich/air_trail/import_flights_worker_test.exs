defmodule Dawarich.AirTrail.ImportFlightsWorkerTest do
  use Dawarich.JobsCase
  use Oban.Testing, repo: Dawarich.ScratchRepo

  alias Dawarich.AirTrail.ImportFlightsWorker
  alias Dawarich.AirTrailStub
  alias Dawarich.Jobs.Processed

  setup do
    rows("TRUNCATE public.flights, public.notifications RESTART IDENTITY CASCADE")
    :ok
  end

  defp user!(settings) do
    [[id]] =
      rows(
        "INSERT INTO users (email, settings, created_at, updated_at) VALUES ('w4-job@example.test', $1, now(), now()) RETURNING id",
        [settings]
      )

    id
  end

  defp configured!(url, extra \\ %{}),
    do: user!(Map.merge(%{"airtrail_url" => url, "airtrail_api_key" => "k"}, extra))

  defp run(user_id, event_id \\ Ecto.UUID.generate()),
    do: perform_job(ImportFlightsWorker, %{"event_id" => event_id, "user_id" => user_id})

  defp fixture_body, do: Jason.encode!(%{"success" => true, "flights" => [AirTrailStub.flight()]})

  test "syncs a configured user and returns :ok" do
    user_id = configured!(AirTrailStub.start(self(), 200, fixture_body()))

    assert run(user_id) == :ok
    assert rows("SELECT external_id FROM flights WHERE user_id = $1", [user_id]) == [[1]]
    assert_received {:airtrail_request, "/api/flight/list", "scope=mine", ["Bearer k"]}
  end

  test "a replayed event is :ok and makes no HTTP call" do
    user_id = configured!(AirTrailStub.start(self(), 200, fixture_body()))
    event_id = Ecto.UUID.generate()
    Processed.mark!(ScratchRepo, event_id, "imports.airtrail_flights")

    assert run(user_id, event_id) == :ok
    refute_received {:airtrail_request, _, _, _}
    assert rows("SELECT count(*) FROM flights") == [[0]]
  end

  test "an unconfigured or deleted user is :ok" do
    url = AirTrailStub.start(self(), 200, fixture_body())
    user_id = configured!(url, %{"airtrail_api_key" => " "})

    assert run(user_id) == :ok

    rows(
      "UPDATE users SET settings = settings || '{\"airtrail_api_key\": \"k\"}', deleted_at = now() WHERE id = $1",
      [user_id]
    )

    assert run(user_id) == :ok
    refute_received {:airtrail_request, _, _, _}
  end

  test "a failed fetch writes one localized error notification and its event, and returns the fixed atom" do
    user_id = configured!(AirTrailStub.start(self(), 500, "{}"), %{"locale" => "de"})

    assert run(user_id) == {:error, :airtrail_sync_failed}

    assert [[notification_id, 2, "AirTrail-Synchronisation fehlgeschlagen", content]] =
             rows("SELECT id, kind, title, content FROM notifications WHERE user_id = $1", [
               user_id
             ])

    assert content =~ "AirTrail responded with 500"
    assert content =~ "Deine AirTrail-Flugdatensynchronisation"

    assert rows("SELECT notification_id FROM phoenix.notification_events") == [
             [notification_id]
           ]
  end

  test "the job's error term carries no URL or key" do
    url = AirTrailStub.start(self(), 500, "{}")
    user_id = configured!(url, %{"airtrail_api_key" => "secret-key"})

    assert {:error, reason} = run(user_id)
    assert reason === :airtrail_sync_failed
  end

  test "decodes only the exact v1 payload" do
    assert ImportFlightsWorker.args_from_command(1, %{"user_id" => 7}) == {:ok, %{"user_id" => 7}}

    assert ImportFlightsWorker.args_from_command(1, %{"user_id" => 7, "import_id" => 1}) ==
             {:error, "invalid_payload"}

    assert ImportFlightsWorker.args_from_command(1, %{"user_id" => "7"}) ==
             {:error, "invalid_payload"}

    assert ImportFlightsWorker.args_from_command(2, %{"user_id" => 7}) ==
             {:error, "unsupported_version"}
  end
end
