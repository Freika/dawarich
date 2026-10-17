defmodule Dawarich.UserData.Export.Tags do
  @moduledoc false
  def write(repo, user, dir, context),
    do: Dawarich.UserData.Export.Serializer.write(repo, user, "tags", dir, context, [])
end
