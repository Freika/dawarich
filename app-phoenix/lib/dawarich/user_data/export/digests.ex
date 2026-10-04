defmodule Dawarich.UserData.Export.Digests do
  @moduledoc false
  alias Dawarich.UserData.Export.Monthly

  def write(repo, user, dir, context),
    do:
      Monthly.write(repo, user, "digests", dir, context, [], Monthly.calendar_month(), fn _id,
                                                                                          pairs ->
        pairs
      end)
end
