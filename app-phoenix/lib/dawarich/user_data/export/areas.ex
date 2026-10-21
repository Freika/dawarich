defmodule Dawarich.UserData.Export.Areas do
  @moduledoc false
  def write(repo, user, dir, context),
    do: Dawarich.UserData.Export.Serializer.write(repo, user, "areas", dir, context, [])
end
