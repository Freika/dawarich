defmodule Dawarich.CLI.Seeds do
  @moduledoc false
  import Dawarich.CLI, only: [puts: 2, fail: 2]

  def seeds([], ctx) do
    :ok = Dawarich.Release.seed(Dawarich.CLI.Migrate.release_opts(ctx))
    puts(ctx, "ordinary seeds: current")
    0
  end

  def seeds(_args, ctx), do: fail(ctx, "usage: dawarich seeds")
end
