defmodule Dawarich.UserData.Export.Exports do
  @moduledoc false
  def write(repo, user, dir, context),
    do:
      Dawarich.UserData.Export.Serializer.write(repo, user, "exports", dir, context, [], "Export")
end
