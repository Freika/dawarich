defmodule Dawarich.Imports.GoogleRecords.DeviceTags do
  @moduledoc false
  alias Dawarich.Imports.JsonStream
  alias Dawarich.Ingest.Ruby

  def reduce(path, acc, fun) do
    state =
      JsonStream.reduce(
        path,
        %{entry: %{}, acc: acc},
        fn
          {:start, :object, [index, "locations"], _}, s when is_integer(index) ->
            %{s | entry: %{}}

          {:value, [key, index, "locations"], value, _, _}, s
          when is_integer(index) and
                 key in ~w(timestamp timestampMs deviceTag latitudeE7 longitudeE7) ->
            entry =
              if key == "timestampMs",
                do:
                  Map.update(s.entry, "timestamp", value, fn v ->
                    if Ruby.truthy?(v), do: v, else: value
                  end),
                else: Map.put(s.entry, key, value)

            %{s | entry: entry}

          {:end, :object, [index, "locations"], _, _}, s when is_integer(index) ->
            p = s.entry

            if Ruby.truthy?(p["timestamp"]) && Ruby.truthy?(p["deviceTag"]),
              do: %{
                s
                | acc:
                    fun.(
                      [p["timestamp"], p["deviceTag"], p["latitudeE7"], p["longitudeE7"]],
                      s.acc
                    )
              },
              else: s

          _, s ->
            s
        end,
        fn
          [key, index, "locations"]
          when is_integer(index) and
                 key in ~w(timestamp timestampMs deviceTag latitudeE7 longitudeE7) ->
            true

          _ ->
            false
        end,
        mode: :saj
      )

    state.acc
  end
end
