defmodule Dawarich.ShareManagement.TrackMutations do
  @moduledoc false
  def run(user, id, action, params, locale, opts \\ []),
    do: Dawarich.ShareManagement.Mutations.run(user, "track", id, action, params, locale, opts)
end
