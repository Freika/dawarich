defmodule Dawarich.Trips.WebDescription do
  @moduledoc false
  alias Dawarich.TripDescription

  def prepare(raw, previous) do
    with {:ok, _} <- TripDescription.read(previous) do
      case raw do
        :omitted ->
          {:ok, :unchanged}

        nil ->
          {:ok, nil}

        body when is_binary(body) ->
          case TripDescription.read(body) do
            {:ok, normalized} -> {:ok, normalized || ""}
            :rails -> {:replay, "trip description content"}
          end

        _ ->
          {:replay, "trip description shape"}
      end
    else
      _ -> {:replay, "existing trip description content"}
    end
  end
end
