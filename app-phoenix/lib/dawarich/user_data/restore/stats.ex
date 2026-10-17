defmodule Dawarich.UserData.Restore.Stats do
  @moduledoc false
  alias Dawarich.UserData.Restore.Batch
  alias Dawarich.Ingest.Ruby

  def call(repo, user, data, context) when is_list(data) do
    existing =
      repo.query!("SELECT year,month FROM stats WHERE user_id=$1", [user], log: false).rows
      |> MapSet.new()

    data
    |> Enum.filter(&valid?/1)
    |> Enum.reject(&MapSet.member?(existing, [&1["year"], &1["month"]]))
    |> Enum.map(fn row ->
      row
      |> Map.drop(~w(created_at updated_at sharing_uuid))
      |> Map.merge(%{
        "user_id" => user,
        "created_at" => context.now,
        "updated_at" => context.now,
        "sharing_uuid" => Ecto.UUID.generate()
      })
    end)
    |> then(&Batch.write(repo, "stats", &1, context))
  end

  def call(_, _, _, _), do: 0

  defp valid?(row) when is_map(row) do
    month = row["month"]

    integer =
      cond do
        is_integer(month) ->
          month

        is_float(month) and trunc(month) == month ->
          trunc(month)

        is_binary(month) ->
          case Integer.parse(month, 10) do
            {n, ""} -> n
            _ -> nil
          end

        true ->
          nil
      end

    Ruby.present?(row["year"]) and Ruby.present?(row["distance"]) and integer != nil and
      integer in 1..12
  end

  defp valid?(_), do: false
end
