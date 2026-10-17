defmodule Dawarich.ShareManagement.TimelineMutations do
  @moduledoc false
  def run(user, action, params, locale, opts \\ []),
    do:
      Dawarich.ShareManagement.Mutations.run(user, "timeline", nil, action, params, locale, opts)
end
