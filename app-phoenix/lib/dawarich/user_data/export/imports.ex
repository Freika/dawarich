defmodule Dawarich.UserData.Export.Imports do
  @moduledoc false
  def write(repo, user, dir, context),
    do:
      Dawarich.UserData.Export.Serializer.write(
        repo,
        user,
        "imports",
        dir,
        context,
        ["raw_data"],
        "Import"
      )
end
