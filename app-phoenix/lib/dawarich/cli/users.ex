defmodule Dawarich.CLI.Users do
  @moduledoc false

  import Dawarich.CLI, only: [puts: 2]

  alias Dawarich.ReleaseMigration

  @activate "UPDATE users SET status = 1 WHERE deleted_at IS NULL"

  def activate(_args, ctx) do
    if ReleaseMigration.self_hosted?(ctx.env) do
      puts(ctx, "Activating all users...")
      ctx.repo.query!(@activate, [], log: false)
      puts(ctx, "All users have been activated")
      0
    else
      puts(ctx, "This task is only available for self-hosted users")
      1
    end
  end
end
