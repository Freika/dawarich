defmodule Dawarich.CLI.RawDataStorageTest do
  use ExUnit.Case, async: false

  alias Dawarich.CLI.RawData

  defp dir!(name, storage?) do
    path = Path.join(System.tmp_dir!(), "a12e-#{name}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(if storage?, do: Path.join(path, "storage"), else: path)
    on_exit(fn -> File.rm_rf(path) end)
    path
  end

  defp ready(env), do: RawData.ready(%{env: env, archive_key: "unused"})

  test "local storage resolves from APP_PATH, never from the working directory" do
    app = dir!("app", true)

    File.cd!(dir!("cwd", true), fn ->
      assert ready(%{"APP_PATH" => app}).storage.root == Path.join(app, "storage")
      assert_raise RuntimeError, ~r/APP_PATH is not set/, fn -> ready(%{}) end
    end)
  end

  test "an APP_PATH without a storage directory is refused for local storage" do
    app = dir!("bare", false)

    assert_raise RuntimeError, ~r/storage is not a directory/, fn ->
      ready(%{"APP_PATH" => app})
    end
  end
end
