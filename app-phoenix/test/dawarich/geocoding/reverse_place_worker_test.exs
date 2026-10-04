defmodule Dawarich.Geocoding.ReversePlaceWorkerTest do
  use Dawarich.GeocodingCase, async: false

  alias Dawarich.Geocoding.ReversePlaceWorker

  test "geocodes the place, treats a missing place as done and lets a raise retry" do
    f = load!("place_name_locked")
    stub_requests!(f["requests"])

    assert ReversePlaceWorker.perform(job(f["place_id"])) == :ok

    assert [[true]] =
             rows("SELECT reverse_geocoded_at IS NOT NULL FROM places WHERE id = $1", [
               f["place_id"]
             ])

    ExUnit.CaptureLog.capture_log(fn ->
      assert ReversePlaceWorker.perform(job(424_242)) == :ok
    end)

    ScratchRepo.query!("TRUNCATE places, instance_settings RESTART IDENTITY CASCADE", [],
      log: false
    )

    clear_response_cache!()
    too_long = load!("place_name_too_long")
    stub_requests!(too_long["requests"])

    assert_raise ArgumentError, fn -> ReversePlaceWorker.perform(job(too_long["place_id"])) end
  end

  test "decoders" do
    assert ReversePlaceWorker.args_from_command(1, %{"place_id" => 7}) ==
             {:ok, %{"place_id" => 7}}

    assert ReversePlaceWorker.args_from_command(1, %{"place_id" => "7"}) ==
             {:error, "invalid_payload"}

    assert ReversePlaceWorker.args_from_command(1, %{"place_id" => 7, "extra" => 1}) ==
             {:error, "invalid_payload"}

    assert ReversePlaceWorker.args_from_command(1, %{}) == {:error, "invalid_payload"}

    assert ReversePlaceWorker.args_from_command(2, %{"place_id" => 7}) ==
             {:error, "unsupported_version"}
  end

  test "queue, attempts and timeout" do
    changeset = ReversePlaceWorker.new(%{"place_id" => 7})
    assert changeset.changes.queue == "reverse_geocoding"
    assert changeset.changes.max_attempts == 4
    refute Map.has_key?(changeset.changes, :unique)
    assert ReversePlaceWorker.timeout(%Oban.Job{}) == :timer.minutes(10)
  end

  defp job(place_id),
    do: %Oban.Job{
      args: %{"event_id" => Ecto.UUID.generate(), "place_id" => place_id},
      attempt: 1,
      max_attempts: 4
    }
end
