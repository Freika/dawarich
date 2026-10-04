defmodule Dawarich.Digests.SettingsTest do
  use ExUnit.Case, async: true

  alias Dawarich.UserSettings

  test "digest toggles match Rails Boolean casting and new-key precedence" do
    corpus =
      __DIR__
      |> Path.join("../../fixtures/a12d1b2/jobs.json")
      |> File.read!()
      |> Jason.decode!()

    assert length(corpus["toggles"]) == 130

    for row <- corpus["toggles"] do
      key = row["kind"] <> "_digest_emails_enabled"

      assert UserSettings.digest?(%{settings: row["settings"]}, key) == (row["enabled"] == true),
             inspect(row)
    end
  end
end
