defmodule Dawarich.PublicPresentationTest do
  use Dawarich.DataCase, async: true

  test "native public gallery accepts M5 values and keeps only admitted thumbnail metadata" do
    photo = %{
      "id" => "synthetic",
      "source" => "immich",
      "thumbnail_url" => "/synthetic/thumbnail",
      "taken_at" => nil,
      "latitude" => 51.0,
      "longitude" => 12.0
    }

    resource = %{
      photos: [photo],
      days: [],
      unit: "km",
      started_at: ~N[2026-03-01 00:00:00],
      ended_at: ~N[2026-03-01 23:59:59]
    }

    page = %{link: %{type: "trip"}, resource: resource}
    presentation = Dawarich.Maps.PublicPresentation.project(page, false)
    [safe] = presentation.resource.photos
    assert safe["id"] == "synthetic"
    assert safe["thumbnail_url"] == "/synthetic/thumbnail"
    refute Map.has_key?(safe, "latitude")
    refute Map.has_key?(safe, "longitude")
  end
end
