defmodule Dawarich.AirTrail.ImportFlightsWorkerTest do
  use Dawarich.JobsCase
  use Oban.Testing, repo: Dawarich.ScratchRepo

  import ExUnit.CaptureLog

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

  defp fixture_body(flight \\ AirTrailStub.flight()),
    do: Jason.encode!(%{"success" => true, "flights" => [flight]})

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

  test "neither the job's error nor the notification carries the URL or key" do
    url = AirTrailStub.start(self(), 500, "{}")
    user_id = configured!(url, %{"airtrail_api_key" => "secret-key"})

    result = inspect(run(user_id))
    [[content]] = rows("SELECT content FROM notifications WHERE user_id = $1", [user_id])

    for text <- [result, content], secret <- ["secret-key", url], do: refute(text =~ secret)
  end

  test "reads offset-less times in the IANA zone of a Rails TIME_ZONE alias" do
    saved = System.get_env("TIME_ZONE")

    on_exit(fn ->
      if saved, do: System.put_env("TIME_ZONE", saved), else: System.delete_env("TIME_ZONE")
    end)

    System.put_env("TIME_ZONE", "Berlin")
    flight = AirTrailStub.flight(%{"departure" => "2026-04-20T12:00:00"})
    user_id = configured!(AirTrailStub.start(self(), 200, fixture_body(flight)))

    assert run(user_id) == :ok
    [[departure]] = rows("SELECT departure_time FROM flights WHERE user_id = $1", [user_id])
    assert NaiveDateTime.truncate(departure, :second) == ~N[2026-04-20 10:00:00]
  end

  test "a flight the store rejects fails with a fixed reason and logs no flight data" do
    flight = AirTrailStub.flight(%{"id" => nil})
    user_id = configured!(AirTrailStub.start(self(), 200, fixture_body(flight)))
    Oban.Telemetry.attach_default_logger(level: :warning, events: [:job])
    on_exit(fn -> Oban.Telemetry.detach_default_logger() end)

    log =
      capture_log(fn ->
        assert run(user_id) == {:error, {:store_failed, :not_null_violation}}
      end)

    assert log =~ "store_failed"
    for leak <- ["Failing row", "52.351", "EDDB", "Air France"], do: refute(log =~ leak)
    assert rows("SELECT count(*) FROM notifications") == [[0]]
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
