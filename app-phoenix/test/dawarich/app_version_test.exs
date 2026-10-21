defmodule Dawarich.AppVersionTest do
  use Dawarich.JobsCase

  alias Dawarich.{AppVersion, ScratchRepo}

  setup do
    previous = System.get_env("RAILS_ENV")

    on_exit(fn ->
      if previous,
        do: System.put_env("RAILS_ENV", previous),
        else: System.delete_env("RAILS_ENV")
    end)

    %{now: DateTime.utc_now()}
  end

  test "a fresh newer release shows outside production only", %{now: now} do
    insert_version("999.0.0", now)
    System.put_env("RAILS_ENV", "development")
    assert AppVersion.update_available?(now)
    System.put_env("RAILS_ENV", "production")
    refute AppVersion.update_available?(now)
  end

  test "a row older than six hours is ignored", %{now: now} do
    insert_version("999.0.0", DateTime.add(now, -7 * 3600))
    System.put_env("RAILS_ENV", "development")
    refute AppVersion.update_available?(now)
  end

  test "an equal or older release does not show an update", %{now: now} do
    System.put_env("RAILS_ENV", "development")

    for version <- [AppVersion.current(), "0.0.0"] do
      insert_version(version, now)
      refute AppVersion.update_available?(now)
      Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(phoenix.app_version))
    end
  end

  defp insert_version(version, checked_at) do
    ScratchRepo.query!(
      "INSERT INTO phoenix.app_version (latest_version, checked_at) VALUES ($1, $2)",
      [version, checked_at]
    )
  end
end
