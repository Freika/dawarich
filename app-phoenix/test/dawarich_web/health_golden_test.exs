defmodule DawarichWeb.HealthGoldenTest do
  use ExUnit.Case, async: false

  test "health replies match the Rails health corpus" do
    corpus = Jason.decode!(File.read!("test/fixtures/admin_pages/api_health.json"))
    assert corpus["version"] == Dawarich.AppVersion.current()
    cases = corpus["cases"]
    assert length(cases) >= 20

    for name <- ~w(unknown absent stale ok alarm) do
      reply = Enum.find(cases, &(&1["name"] == name))
      assert reply["status"] == 200
      assert reply["body"]["status"] == "ok"
      assert Map.keys(reply["body"]["phoenix"]) |> Enum.sort() == ~w(alarm status)
    end

    for name <- ~w(query_valid query_invalid bearer_valid bearer_invalid query_precedence pending cloud_ok cloud_throttled ready_ok ready_database_error ready_redis_error ready_pending) do
      assert Enum.any?(cases, &(&1["name"] == name))
    end
  end
end
