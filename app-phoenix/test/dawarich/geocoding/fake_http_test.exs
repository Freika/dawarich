defmodule Dawarich.Geocoding.FakeHttpTest do
  use ExUnit.Case, async: true

  alias Dawarich.Geocoding.FakeHttp

  setup do
    start_supervised!(FakeHttp)
    :ok
  end

  test "serves recorded bodies and records requests" do
    url = "https://photon.example.test/reverse?lat=51.3397&lon=12.3731"
    FakeHttp.stub(url, 200, ~s({"type":"FeatureCollection","features":[]}))

    assert FakeHttp.get(url) == {200, ~s({"type":"FeatureCollection","features":[]})}
    assert FakeHttp.requests() == [url]
  end

  test "raises for a URL with no recorded response" do
    FakeHttp.stub("https://photon.example.test/reverse?lat=1&lon=2", 200, "{}")

    assert_raise RuntimeError, ~r/no recorded response/, fn ->
      FakeHttp.get("https://photon.example.test/reverse?lat=9&lon=9")
    end
  end
end
