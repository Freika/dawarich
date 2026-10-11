defmodule Dawarich.Build.NativeJobOwnerIsolationTest do
  use ExUnit.Case, async: true

  @files [
    "test/dawarich/areas/commands_test.exs",
    "test/dawarich/claimed_upload_cleanup_test.exs",
    "test/dawarich/native_derivative_purge_test.exs",
    "test/dawarich/route_videos/scoped_test.exs",
    "test/dawarich/trips/commands_test.exs",
    "test/dawarich/trips/web_commands_test.exs",
    "test/dawarich_web/native_family_commands_test.exs",
    "test/dawarich_web/native_family_presentation_test.exs",
    "test/dawarich_web/native_trip_effects_test.exs",
    "test/dawarich_web/native_video_gallery_test.exs",
    "test/dawarich_web/native_video_studio_test.exs"
  ]

  test "command host tests serialize shared job owner locks across sandbox lifetimes" do
    for file <- @files do
      source = File.read!(file)
      assert String.contains?(source, "async: false"), file
      refute String.contains?(source, "async: true"), file
    end
  end
end
