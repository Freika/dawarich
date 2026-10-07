defmodule Dawarich.Release.LifecycleTest do
  use ExUnit.Case, async: true

  alias Dawarich.Release.Lifecycle

  test "L1 final Cloud admission refuses invalid flags drain mode missing secrets and incomplete provisioning" do
    env = %{
      "SELF_HOSTED" => "false",
      "MANAGER_URL" => "https://manager.example.invalid",
      "JWT_SECRET_KEY" => "synthetic-admission-key",
      "DATABASE_SESSION_URL" => "postgres://session.example.invalid/cloud",
      "DAWARICH_RAILS" => "off"
    }

    assert Lifecycle.mode(env) == {:ok, :native}
    assert Lifecycle.mode(Map.put(env, "DAWARICH_PHOENIX_LIFECYCLE", "false")) == {:ok, :native}

    for flag <- ["", "TRUE", "1", "yes", " false", "true ", "'true'"] do
      assert Lifecycle.mode(Map.put(env, "DAWARICH_PHOENIX_LIFECYCLE", flag)) ==
               {:error, :invalid_lifecycle_flag}
    end

    for flag <- ["true", "invalid", "", "TRUE"] do
      assert Lifecycle.mode(Map.put(env, "DAWARICH_CLOUD_DRAIN_ONLY", flag)) ==
               {:error, :cloud_native_lifecycle}
    end
  end

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
