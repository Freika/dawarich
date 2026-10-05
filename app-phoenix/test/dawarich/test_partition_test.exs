defmodule Dawarich.TestPartitionTest do
  use ExUnit.Case, async: false

  test "each partition isolates every configured external resource" do
    variables = ~w(MIX_TEST_PARTITION PHOENIX_TEST_DATABASE PHOENIX_TEST_REDIS_URL)
    previous = Map.new(variables, &{&1, System.get_env(&1)})

    try do
      System.put_env("PHOENIX_TEST_DATABASE", "dawarich_phoenix_test_part")
      System.put_env("PHOENIX_TEST_REDIS_URL", "redis://127.0.0.1:7271/1")

      for partition <- 1..4 do
        System.put_env("MIX_TEST_PARTITION", to_string(partition))
        config = Config.Reader.read!("config/test.exs", env: :test)[:dawarich]
        database = "dawarich_phoenix_test_part#{partition}"

        for {repo, suffix} <- [
              {Dawarich.Repo, ""},
              {Dawarich.ScratchRepo, "_scratch"},
              {Dawarich.ScratchCaseRepo, "_scratch_case"},
              {Dawarich.TracksScratchRepo, "_scratch_tracks"}
            ] do
          assert config[repo][:database] == database <> suffix
        end

        assert config[:redis][:url] == "redis://127.0.0.1:#{7270 + partition}/1"
        assert config[:cable_prefix] == "dawarich_a12a_part#{partition}"
        assert config[:test_tmp_dir] == Path.expand("tmp/partitions/#{partition}/system")
        assert config[:i18n_path] == Path.expand("tmp/partitions/#{partition}/i18n.json")

        assert config[:achievements_path] ==
                 Path.expand("tmp/partitions/#{partition}/achievements.json")
      end
    after
      for {name, value} <- previous do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end
  end
end
