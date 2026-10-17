defmodule Dawarich.Admin.InstanceExperimentalInputTest do
  use ExUnit.Case, async: true

  alias Dawarich.Admin.InstanceInput

  test "enabling map matching without atlas_url is rejected with atlas_url_required" do
    error = "Set an Atlas URL before enabling map matching."
    assert {:invalid, ^error} = prepare(%{"map_matching_enabled" => "true"})
    assert {:invalid, ^error} = prepare(%{"atlas_url" => " "}, %{"map_matching_enabled" => true})
    assert {:invalid, ^error} = prepare(%{}, %{}, %{"MAP_MATCHING_ENABLED" => "true"})

    assert {:ok, _} =
             prepare(%{"map_matching_enabled" => "true"}, %{}, %{
               "ATLAS_URL" => "http://atlas.example.invalid"
             })

    assert {:ok, _} =
             prepare(%{"map_matching_enabled" => "true"}, %{
               "atlas_url" => "http://atlas.example.invalid"
             })

    assert {:invalid, ^error} =
             prepare(%{"map_matching_enabled" => "false"}, %{}, %{
               "MAP_MATCHING_ENABLED" => "true"
             })

    assert {:ok, _} =
             prepare(%{"map_matching_enabled" => "true"}, %{}, %{
               "MAP_MATCHING_ENABLED" => "false"
             })
  end

  test "atlas_url rejects userinfo, query, fragment and non-http schemes; strips trailing slash" do
    error =
      "Atlas URL must be a full HTTP or HTTPS URL without credentials, a query, or a fragment."

    for url <- [
          "http://user:password@atlas.example.invalid",
          "http://atlas.example.invalid?x=1",
          "http://atlas.example.invalid#part",
          "ftp://atlas.example.invalid",
          "/relative",
          "http://",
          "http://bad host",
          "http://atlas.example.invalid?",
          "http://atlas.example.invalid#"
        ] do
      assert {:invalid, ^error} = prepare(%{"atlas_url" => url}), url
    end

    for url <- ["http://127.0.0.1:8000", "https://atlas.example.invalid/api", "http://[::1]:8000"] do
      assert {:ok, [{"atlas_url", ^url}]} = prepare(%{"atlas_url" => " #{url}/// "})
    end

    assert {:ok, [{"atlas_url", nil}]} = prepare(%{"atlas_url" => " "})

    assert {:ok, _} =
             prepare(%{"atlas_url" => "bad"}, %{}, %{
               "ATLAS_URL" => "http://pinned.example.invalid"
             })

    assert {:invalid, ^error} =
             prepare(%{"map_matching_enabled" => "true"}, %{}, %{
               "ATLAS_URL" => "ftp://invalid.example.invalid"
             })
  end

  defp prepare(values, resolved \\ %{}, env \\ %{}) do
    InstanceInput.prepare(%{"instance_settings" => values}, resolved, env, "en")
  end
end
