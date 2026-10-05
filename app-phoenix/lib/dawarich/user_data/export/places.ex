defmodule Dawarich.UserData.Export.Places do
  @moduledoc false
  def write(repo, user, dir, context),
    do: Dawarich.UserData.Export.Serializer.write(repo, user, "places", dir, context, [])
end
