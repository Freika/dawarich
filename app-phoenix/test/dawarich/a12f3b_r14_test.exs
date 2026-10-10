defmodule Dawarich.A12f3bR14Test do
  use Dawarich.JobsCase

  alias Dawarich.Achievements.CheckWorker
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Points.NativeEffects
  alias Dawarich.Wave6Fixtures

  setup do
    saved = System.get_env("DAWARICH_RAILS")

    on_exit(fn ->
      if saved,
        do: System.put_env("DAWARICH_RAILS", saved),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    :ok
  end

  @tag a12f3b_case: "R14helper"
  test "point achievements helper honours native command ownership and Rails hand-back" do
    for {mode, owner} <- [{"on", :oban}, {"off", :oban}, {"off", :sidekiq}] do
      Dawarich.JobsCase.reset!(ScratchRepo)
      System.put_env("DAWARICH_RAILS", mode)
      Ownership.put!(ScratchRepo, "command:achievements.check", owner)
      user = Wave6Fixtures.user!()
      Wave6Fixtures.point!(user)
      payload = %{"user_id" => user, "oldest_timestamp" => nil}
      assert NativeEffects.achievements(ScratchRepo, payload) == :ok
      assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]

      assert [["Dawarich.Achievements.CheckWorker", args]] =
               rows("SELECT worker,args FROM oban.oban_jobs")

      assert args == Map.put(payload, "notify", true)
      assert CheckWorker.perform(%Oban.Job{args: args}) == :ok
      assert CheckWorker.perform(%Oban.Job{args: args}) == :ok

      assert [[3]] =
               rows(
                 "SELECT (state->>'calculation_version')::int FROM achievement_progresses WHERE user_id=$1",
                 [user]
               )

      assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    end

    Dawarich.JobsCase.reset!(ScratchRepo)
    System.put_env("DAWARICH_RAILS", "on")
    Ownership.put!(ScratchRepo, "command:achievements.check", :sidekiq)
    payload = %{"user_id" => 7, "oldest_timestamp" => 123}
    assert NativeEffects.achievements(ScratchRepo, payload) == :ok

    assert rows("SELECT kind,payload FROM phoenix.rails_commands") == [
             ["achievements.check", payload]
           ]

    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
  end
end
