defmodule Dawarich.Users.RecalculationArgsTest do
  use Dawarich.JobsCase

  alias Dawarich.RecalculationFixtures, as: Fixtures
  alias Dawarich.Users.RecalculationArgs, as: Args

  test "decodes only versioned id-only recalculation payloads" do
    source_id = "00000000-0000-4000-8000-000000170001"
    base = %{"source_job_id" => source_id}
    user = Map.put(base, "user_id", 170_101)
    zoned = Map.put(base, "ambient_zone", "Europe/Berlin")
    zoned_user = Map.merge(user, zoned)

    payloads = [
      {"stats.full_recalculation", user},
      {"users.recalculate_data",
       Map.merge(zoned_user, %{"year" => 2025, "notify" => true, "job_queue" => nil})},
      {"points.anomaly_backfill",
       Map.merge(zoned_user, %{
         "reset" => true,
         "notify" => false,
         "rebuild" => "inline",
         "progress" => %{}
       })},
      {"release.anomalies", Map.put(zoned, "limit", 2)},
      {"release.anomalies_user", Map.put(zoned_user, "attempt", 1)},
      {"release.per_tracker", zoned_user}
    ]

    for {type, payload} <- payloads do
      assert Args.decode(type, 1, payload) == {:ok, payload}, type

      for key <- Map.keys(payload) do
        assert Args.decode(type, 1, Map.delete(payload, key)) == {:error, "invalid_payload"},
               "#{type}: missing #{key}"

        for value <- invalid_values(key) do
          assert Args.decode(type, 1, Map.put(payload, key, value)) ==
                   {:error, "invalid_payload"},
                 "#{type}: #{key}=#{inspect(value)}"
        end

        if key == "user_id" and type != "release.per_tracker" do
          assert Args.decode(type, 1, Map.put(payload, key, nil)) == {:error, "invalid_payload"}
        end
      end

      for extra <- ~w(event_id operation_id cursor rebuild_attempt objects) do
        assert Args.decode(type, 1, Map.put(payload, extra, %{})) == {:error, "invalid_payload"}
      end

      for invalid <- [nil, [], %{}, "object"] do
        assert Args.decode(type, 1, invalid) == {:error, "invalid_payload"}
      end

      for version <- [nil, 0, 2, "1", 1.0] do
        assert Args.decode(type, version, payload) == {:error, "unsupported_version"}
      end
    end

    assert Args.decode("unknown", 1, user) == {:error, "invalid_payload"}
    {_, user_payload} = Enum.at(payloads, 1)

    for year <- [nil, 0, -1], notify <- [false, true], queue <- [nil, "low_priority"] do
      payload =
        Map.merge(user_payload, %{"year" => year, "notify" => notify, "job_queue" => queue})

      assert Args.decode("users.recalculate_data", 1, payload) == {:ok, payload}
    end

    {_, backfill} = Enum.at(payloads, 2)
    interrupted = Fixtures.case!("backfill_interrupted")
    progress = interrupted["expected"]["jobs"] |> hd() |> Map.fetch!("continuation")

    for state <- [
          %{},
          %{"completed" => []},
          progress,
          %{"completed" => ~w(reset_flags filter_months)}
        ],
        rebuild <- ~w(inline async) do
      payload = Map.merge(backfill, %{"progress" => state, "rebuild" => rebuild})
      assert Args.decode("points.anomaly_backfill", 1, payload) == {:ok, payload}
    end

    for attempt <- 1..8 do
      payload = Map.put(zoned_user, "attempt", attempt)
      assert Args.decode("release.anomalies_user", 1, payload) == {:ok, payload}
    end

    payload = Map.put(zoned_user, "user_id", nil)
    assert Args.decode("release.per_tracker", 1, payload) == {:ok, payload}
    kase = Fixtures.case!("full")
    assert Fixtures.load!(ScratchRepo, kase) == :ok

    assert rows("SELECT settings FROM users WHERE id = $1", [170_101]) ==
             [[hd(kase["input"]["users"])["settings"]]]

    assert rows("SELECT count(*) FROM points WHERE user_id = $1 AND anomaly IS TRUE", [170_101]) ==
             [[1]]
  end

  defp invalid_values("source_job_id"),
    do: [nil, false, 1, "", "not-a-uuid", "00000000-0000-4000-8000-00000017000Z", %{}, []]

  defp invalid_values("user_id"), do: [false, "170101", 1.5, %{}, []]
  defp invalid_values("year"), do: [true, "2025", "", 2025.5, %{}, []]
  defp invalid_values(key) when key in ~w(reset notify), do: [nil, 0, "false", "", %{}, []]
  defp invalid_values("job_queue"), do: ["", false, 0, %{}, []]
  defp invalid_values("ambient_zone"), do: [nil, false, 0, %{}, []]
  defp invalid_values("rebuild"), do: [nil, false, "later", "", %{}, []]
  defp invalid_values("limit"), do: [nil, false, 0, -1, 1.5, "2", %{}, []]
  defp invalid_values("attempt"), do: [nil, false, 0, 9, 1.5, "1", %{}, []]

  defp invalid_values("progress"),
    do: [
      nil,
      [],
      false,
      %{"unknown" => true},
      %{"completed" => "reset_flags"},
      %{"completed" => ["unknown"]},
      %{"completed" => ~w(filter_months reset_flags)},
      %{"completed" => [], "current" => ["filter_months", 1]},
      %{"completed" => ["reset_flags"], "current" => ["other", 1]},
      %{"completed" => ["reset_flags"], "current" => ["filter_months", "1"]},
      %{"completed" => ["reset_flags"], "current" => ["filter_months", -1]},
      %{"completed" => ["reset_flags"], "current" => ["filter_months", 1], "object" => %{}}
    ]
end
