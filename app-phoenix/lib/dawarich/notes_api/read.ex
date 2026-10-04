defmodule Dawarich.NotesApi.Read do
  @moduledoc false

  alias Dawarich.RailsTime
  alias Dawarich.NotesApi.Payload
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def index(owner, params, zone) do
    RailsTime.with_zone(zone, fn ->
      with {:ok, where, values} <- filters(params, "n.user_id = $1", [owner]) do
        rows = Payload.rows(where, values, " ORDER BY n.noted_at DESC")

        if length(rows) == length(Enum.uniq_by(rows, &List.last/1)),
          do: {:ok, Enum.map(rows, &Payload.term/1)},
          else: {:replay, "notes timestamp ties"}
      end
    end)
  end

  def show(owner, id, zone) do
    RailsTime.with_zone(zone, fn ->
      case Payload.rows("n.user_id = $1 AND n.id = $2", [owner, id]) do
        [row] -> {:ok, Payload.term(row)}
        [] -> :not_found
      end
    end)
  end

  defp filters(params, where, values) do
    Enum.reduce_while(~w(attachable_type attachable_id), {:ok, where, values}, fn key,
                                                                                  {:ok, where,
                                                                                   values} ->
      value = params[key]

      cond do
        Ruby.blank?(value) ->
          {:cont, {:ok, where, values}}

        key == "attachable_type" and is_binary(value) ->
          {:cont,
           {:ok, where <> " AND n.attachable_type = $#{length(values) + 1}", values ++ [value]}}

        key == "attachable_id" and
            (is_integer(value) or (is_binary(value) and value =~ ~r/\A\d{1,18}\z/)) ->
          id = if is_integer(value), do: value, else: String.to_integer(value)
          {:cont, {:ok, where <> " AND n.attachable_id = $#{length(values) + 1}", values ++ [id]}}

        true ->
          {:halt, {:replay, "note filter shape"}}
      end
    end)
    |> case do
      {:ok, where, values} ->
        where =
          if params["standalone"] == "true",
            do: where <> " AND n.attachable_id IS NULL",
            else: where

        {:ok, where, values}

      replay ->
        replay
    end
  end
end
