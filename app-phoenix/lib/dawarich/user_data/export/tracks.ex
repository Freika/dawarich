defmodule Dawarich.UserData.Export.Tracks do
  @moduledoc false
  alias Dawarich.UserData.Export.{Monthly, Serializer}

  def write(repo, user, dir, context) do
    columns = Serializer.columns(repo, "track_segments", ~w(track_id))

    Monthly.write(
      repo,
      user,
      "tracks",
      dir,
      context,
      [],
      Monthly.timestamp_month("start_at"),
      fn id, pairs ->
        segments =
          Serializer.pages(repo, id, "track_segments", columns, context.zone, [], "track_id")
          |> Enum.map(fn [_id | values] ->
            %Jason.OrderedObject{
              values:
                Enum.zip_with(columns, values, fn {name, type}, value ->
                  {name, Serializer.value("track_segments", name, type, value)}
                end)
            }
          end)

        pairs ++ [{"segments", segments}]
      end
    )
  end
end
