defmodule Dawarich.Release.LifecycleTest do
  use ExUnit.Case, async: true

  alias Dawarich.Release.Lifecycle

  test "lifecycle is off by default and rejects invalid or Cloud-on configuration" do
    assert Lifecycle.mode(%{}) == {:ok, :rails}
    assert Lifecycle.mode(%{"SELF_HOSTED" => "false"}) == {:ok, :rails}

    for hosted <- ["true", "false"] do
      assert Lifecycle.mode(%{"DAWARICH_PHOENIX_LIFECYCLE" => "false", "SELF_HOSTED" => hosted}) ==
               {:ok, :rails}
    end

    assert Lifecycle.mode(%{"DAWARICH_PHOENIX_LIFECYCLE" => "true"}) == {:ok, :native}

    assert Lifecycle.mode(%{"DAWARICH_PHOENIX_LIFECYCLE" => "true", "SELF_HOSTED" => " 'ON' "}) ==
             {:ok, :native}

    assert Lifecycle.mode(%{"DAWARICH_PHOENIX_LIFECYCLE" => "true", "SELF_HOSTED" => "false"}) ==
             {:error, :cloud_native_lifecycle}

    for flag <- ["", "TRUE", "1", "yes", " false", "true ", "'true'"] do
      assert Lifecycle.mode(%{"DAWARICH_PHOENIX_LIFECYCLE" => flag}) ==
               {:error, :invalid_lifecycle_flag}
    end
  end
end
