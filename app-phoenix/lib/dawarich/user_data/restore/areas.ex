defmodule Dawarich.UserData.Restore.Areas do
  @moduledoc false
  alias Dawarich.UserData.Restore.Batch
  alias Dawarich.Ingest.Ruby

  def call(repo, user, data, context) when is_list(data) do
    existing =
      repo.query!(
        "SELECT name,latitude::float8,longitude::float8 FROM areas WHERE user_id=$1",
        [user],
        log: false
      ).rows
      |> MapSet.new()

    data
    |> Enum.filter(
      &(is_map(&1) and
          Enum.all?(~w(name latitude longitude), fn key -> Ruby.present?(&1[key]) end))
    )
    |> Enum.map(fn area ->
      area
      |> Map.drop(~w(created_at updated_at))
      |> Map.merge(%{"user_id" => user, "created_at" => context.now, "updated_at" => context.now})
      |> Map.put("radius", if(area["radius"] in [nil, false], do: 100, else: area["radius"]))
    end)
    |> Enum.reject(
      &MapSet.member?(existing, [
        &1["name"],
        Ruby.to_f(&1["latitude"]),
        Ruby.to_f(&1["longitude"])
      ])
    )
    |> then(&Batch.write(repo, "areas", &1, context))
  end

  def call(_, _, _, _), do: 0
end
