defmodule Dawarich.RegistrySelectionTest do
  use ExUnit.Case, async: true

  @tag :a12f4_a07_2
  test "idle role supervises no job producers or dependencies in either runtime mode" do
    for standalone <- [nil, "off"], hosted <- [nil, "true", "false"] do
      env = %{
        "DAWARICH_RAILS" => standalone,
        "DAWARICH_PROCESS_ROLE" => "sidekiq_idle",
        "SELF_HOSTED" => hosted
      }

      assert Dawarich.Application.plan(nil, env) == :sidekiq_idle
      assert Dawarich.Application.children(:sidekiq_idle) == []

      {:ok, supervisor} =
        Supervisor.start_link(Dawarich.Application.children(:sidekiq_idle),
          strategy: :one_for_one
        )

      assert Supervisor.which_children(supervisor) == []
      monitor = Process.monitor(supervisor)
      assert Supervisor.stop(supervisor) == :ok
      assert_receive {:DOWN, ^monitor, :process, ^supervisor, :normal}
    end

    assert Dawarich.Standalone.job_entries(%{}) == []

    assert Dawarich.Standalone.job_entries(%{
             "DAWARICH_OBAN_JOB_KEYS" => "command:visits.suggest"
           }) ==
             Dawarich.Jobs.Claimer.entries("command:visits.suggest")
  end
end
