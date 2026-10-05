defmodule Dawarich.UserData.Export.Notifications do
  @moduledoc false
  def write(repo, user, dir, context),
    do: Dawarich.UserData.Export.Serializer.write(repo, user, "notifications", dir, context, [])
end
