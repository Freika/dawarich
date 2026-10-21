defmodule Dawarich.DataCaseSandboxTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest
  alias Dawarich.{DataCase, Repo}
  alias Dawarich.Test.{TripsNativeUI, TripsSeeds}

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual) end)
    :ok
  end

  test "automatic pool mode preserves the seeded actor in a connected trip form" do
    :ok = DataCase.setup_sandbox(%{async: false})
    TripsSeeds.user!(9_951)
    {:ok, view, _html} = TripsNativeUI.live_as(9_951, "/trips/new")
    assert has_element?(view, "#native-trip-form")
    assert has_element?(view, "input#trip_name")
  end
end
