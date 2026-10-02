for repo <- [
      Dawarich.Repo,
      Dawarich.ScratchRepo,
      Dawarich.ScratchCaseRepo,
      Dawarich.TracksScratchRepo
    ] do
  config = Application.fetch_env!(:dawarich, repo)
  Application.put_env(:dawarich, repo, Keyword.put(config, :pool_size, 2))
end

Logger.configure(level: :warning)
Application.ensure_all_started(:postgrex)
Application.ensure_all_started(:ecto_sql)
Dawarich.Release.migrate_oban()
{:ok, _} = Application.ensure_all_started(:dawarich)
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, :manual)
Code.require_file("test/dawarich/auth/credentials_test.exs")
