defmodule Dawarich.DomainProjectionUtilitiesTest do
  use ExUnit.Case, async: true

  test "domain localization preserves HTML escaping without a web renderer" do
    tree = %{"en" => %{"label_html" => "Hello %{name}"}}

    assert project(Dawarich.Formatting.Translate, :t, [tree, "en", "label_html", %{name: "<b>"}]) ==
             {:safe, "Hello &lt;b&gt;"}
  end

  test "domain parameter projection preserves valid years and typed refusals" do
    assert project(Dawarich.Input.Params, :year, ["2026"]) == {:ok, 2026}
    assert {:replay, _} = project(Dawarich.Input.Params, :year, ["2038"])
    assert {:replay, _} = project(Dawarich.Input.Params, :year, [%{"year" => "2026"}])
  end

  test "domain itinerary URLs preserve escaped source identifiers" do
    plan = %{source: %{base_url: "https://trek.example/"}, trip: %{source_identifier: "a b/"}}

    assert project(Dawarich.Trips.Itinerary, :trek_url, [plan]) ==
             "https://trek.example/trips/a%20b%2F"
  end

  test "domain settings projection filters unknown and restricted fields" do
    attrs = %{"track_color" => "orange", "timezone" => "UTC", "unknown" => "ignored"}

    assert project(Dawarich.Settings.Input, :permit, [attrs, false]) == %{
             "track_color" => "orange",
             "timezone" => "UTC"
           }

    assert project(Dawarich.Settings.Input, :permit, [attrs, true]) == %{"timezone" => "UTC"}
  end

  test "domain share proofs keep their issued identity binding" do
    assert project(Dawarich.Sharing.UnlockToken, :proof_identity, ["synthetic"]) ==
             "a7ef366d8a084c89c7300409a31faea7043f9765e050739e43bcd353721a4fdd"
  end

  test "domain upload input preserves typed transport and refuses spoofed objects" do
    upload = %Plug.Upload{
      path: "synthetic.gpx",
      filename: "synthetic.gpx",
      content_type: "application/gpx+xml"
    }

    assert project(Dawarich.Input.Upload, :cast, [%{"file" => upload}]) == {:ok, upload}
    assert project(Dawarich.Input.Upload, :cast, [%{"file" => Map.from_struct(upload)}]) == :error
    assert project(Dawarich.Input.Upload, :cast, [%{}]) == :error
  end

  defp project(module, function, args) do
    if Code.ensure_loaded?(module),
      do: apply(module, function, args),
      else: {:error, :missing_domain_projection}
  end
end
