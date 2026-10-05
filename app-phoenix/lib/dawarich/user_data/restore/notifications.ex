defmodule Dawarich.UserData.Restore.Notifications do
  @moduledoc false
  alias Dawarich.UserData.Restore.Batch
  alias Dawarich.Ingest.Ruby

  def call(repo, user, data, context) when is_list(data) do
    existing =
      repo.query!("SELECT title,content FROM notifications WHERE user_id=$1", [user], log: false).rows
      |> Enum.map(fn [title, content] -> [strip(title), strip(content)] end)
      |> MapSet.new()

    data
    |> Enum.filter(&(is_map(&1) and Ruby.present?(&1["title"]) and Ruby.present?(&1["content"])))
    |> Enum.map(fn note ->
      note
      |> Map.drop(["updated_at"])
      |> Map.merge(%{"user_id" => user, "updated_at" => context.now})
      |> Map.put(
        "created_at",
        if(Ruby.blank?(note["created_at"]), do: context.now, else: note["created_at"])
      )
    end)
    |> Enum.reject(&MapSet.member?(existing, [strip(&1["title"]), strip(&1["content"])]))
    |> then(&Batch.write(repo, "notifications", &1, context))
  end

  def call(_, _, _, _), do: 0
  defp strip(nil), do: nil

  defp strip(value) when is_binary(value),
    do: Regex.replace(~r/\A[\x00\x09-\x0D ]+|[\x00\x09-\x0D ]+\z/, value, "")
end
