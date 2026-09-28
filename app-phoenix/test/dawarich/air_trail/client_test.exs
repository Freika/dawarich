defmodule Dawarich.AirTrail.ClientTest do
  use ExUnit.Case, async: false

  alias Dawarich.AirTrail.Client
  alias Dawarich.AirTrailStub

  defp source(url), do: %{url: url, api_key: "k", skip_ssl_verification: false}

  test "GETs /api/flight/list?scope=mine with the bearer key and returns the flights" do
    base = AirTrailStub.start(self(), 200, ~s({"success":true,"flights":[{"id":1}]}))

    assert Client.flights(source(base)) == {:ok, [%{"id" => 1}]}
    assert_received {:airtrail_request, "/api/flight/list", "scope=mine", ["Bearer k"]}
  end

  test "strips exactly one trailing slash like Ruby's chomp" do
    base = AirTrailStub.start(self(), 200, ~s({"success":true}))

    assert Client.flights(source(base <> "/")) == {:ok, []}
    assert_received {:airtrail_request, "/api/flight/list", _, _}

    assert Client.flights(source(base <> "//")) == {:ok, []}
    assert_received {:airtrail_request, "//api/flight/list", _, _}
  end

  test "a missing flights key is an empty list" do
    base = AirTrailStub.start(self(), 200, ~s({"success":true}))

    assert Client.flights(source(base)) == {:ok, []}
  end

  test "non-2xx is Ruby's message" do
    base = AirTrailStub.start(self(), 503, ~s({"success":true,"flights":[]}))

    assert Client.flights(source(base)) == {:error, "AirTrail responded with 503"}
  end

  test "success false or missing is Ruby's message" do
    unsuccessful = AirTrailStub.start(self(), 200, ~s({"success":false,"flights":[]}))
    missing = AirTrailStub.start(self(), 200, ~s({}))

    assert Client.flights(source(unsuccessful)) ==
             {:error, "AirTrail returned an unsuccessful response"}

    assert Client.flights(source(missing)) ==
             {:error, "AirTrail returned an unsuccessful response"}
  end

  test "invalid JSON" do
    base = AirTrailStub.start(self(), 200, "nope")

    assert Client.flights(source(base)) == {:error, "AirTrail returned invalid JSON"}
  end

  test "an unreachable host" do
    assert Client.flights(source("http://127.0.0.1:1")) ==
             {:error, "Could not connect to AirTrail"}
  end
end
