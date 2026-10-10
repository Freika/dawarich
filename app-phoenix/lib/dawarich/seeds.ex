defmodule Dawarich.Seeds do
  @moduledoc false

  alias Dawarich.Release.Native
  alias Dawarich.Seeds.{BootstrapUser, Countries, Reference}

  def run(repo, opts) do
    for step <- [&BootstrapUser.run/2, &Countries.run/2, &Reference.regions/2, &Reference.tags/2] do
      Native.fence!(repo, Keyword.fetch!(opts, :lease))
      step.(repo, opts)
    end

    :ok
  rescue
    _ -> raise "ordinary seeds refused"
  end
end
