defmodule Dawarich.Tracks.Owner do
  @moduledoc false

  def lock(repo, key) do
    owner = Dawarich.Jobs.Ownership.lock(repo, key)
    if Dawarich.Standalone.enabled?(), do: :oban, else: owner
  end
end
