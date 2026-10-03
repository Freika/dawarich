defmodule Dawarich.TripDescriptionTest do
  use ExUnit.Case, async: true

  alias Dawarich.TripDescription

  @corpus "test/fixtures/trips/descriptions.json"
  @external_resource @corpus

  for c <- @corpus |> File.read!() |> Jason.decode!() |> Map.fetch!("cases") do
    @case c

    if c["expect"] == "phoenix" do
      test "#{c["name"]}: Phoenix renders the bytes the trip page shows" do
        assert {:ok, description} = TripDescription.read(@case["body"])
        rendered = description && IO.iodata_to_binary(TripDescription.html(description))
        assert rendered == @case["rendered"]
      end
    else
      test "#{c["name"]}: the trip page goes to Rails" do
        assert TripDescription.read(@case["body"]) == :rails
      end
    end
  end

  @tag timeout: 10_000
  test "a long inner whitespace run is read in linear time" do
    body = "<div>a" <> String.duplicate(" ", 400_000) <> "b</div>"
    assert {:ok, ^body} = TripDescription.read(body)
  end
end
