defmodule Dawarich.UserData.Restore.Tags do
  @moduledoc false
  alias Dawarich.Ingest.Ruby
  alias Dawarich.Imports.NormalCast.Text
  alias Dawarich.UserData.Restore.Batch

  def call(repo, user, data, context) when is_list(data) do
    Enum.reduce(data, 0, fn row, count -> count + restore(repo, user, row, context) end)
  end

  def call(_, _, _, _), do: 0

  defp restore(repo, user, row, context) when is_map(row) do
    name = row["name"]

    if Ruby.present?(name) and valid?(row) and
         repo.query!(
           "SELECT id FROM tags WHERE user_id=$1 AND name=$2 LIMIT 1",
           [user, Text.cast(name)],
           log: false
         ).rows == [] do
      row
      |> Map.put("user_id", user)
      |> Map.update("created_at", context.now, &if(Ruby.blank?(&1), do: context.now, else: &1))
      |> Map.update("updated_at", context.now, &if(Ruby.blank?(&1), do: context.now, else: &1))
      |> then(&Batch.create!(repo, "tags", &1, context))
    else
      0
    end
  end

  defp restore(_, _, _, _), do: 0

  defp valid?(row) do
    icon = Text.cast(row["icon"])
    color = Text.cast(row["color"])
    radius = row["privacy_radius_meters"]

    (Ruby.blank?(icon) or
       (length(String.codepoints(icon)) <= 10 and not Regex.match?(~r/\A[a-zA-Z]+\z/, icon))) and
      (Ruby.blank?(color) or Regex.match?(~r/\A#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})\z/, color)) and
      valid_radius?(radius)
  end

  defp valid_radius?(nil), do: true
  defp valid_radius?(""), do: true
  defp valid_radius?(value) when is_number(value), do: value > 0 and value <= 5000

  defp valid_radius?(value) when is_binary(value) do
    case Float.parse(value) do
      {n, ""} -> n > 0 and n <= 5000
      _ -> Ruby.blank?(value)
    end
  end

  defp valid_radius?(_), do: false
end
