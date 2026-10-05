defmodule Dawarich.UserData.Export.Trips do
  @moduledoc false
  def write(repo, user, dir, context),
    do:
      Dawarich.UserData.Export.Serializer.write(repo, user, "trips", dir, context, [
        "trip_source_id"
      ])
end
