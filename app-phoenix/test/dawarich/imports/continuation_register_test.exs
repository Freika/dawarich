defmodule Dawarich.Imports.ContinuationRegisterTest do
  use ExUnit.Case, async: true

  @tag continuation_register: true
  test "the ruling-17 register records the Rails continuation progress regression" do
    register = File.read!(Path.expand("../../../../docs/phoenix/fixed-rails-bugs.md", __DIR__))
    assert register =~ "2,000 → 1,000"
    assert register =~ "app/services/imports/broadcaster.rb:10"
    assert register =~ "app/services/google_maps/records_importer.rb:23"
    assert register =~ "app-phoenix/lib/dawarich/imports/gpx_progress.ex:13"
    assert register =~ "retrying a predecessor never lowers durable import progress"
    assert register =~ "F17 progress: no ED/DRB row added"
  end
end
