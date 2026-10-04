defmodule Dawarich.Places.WebTags do
  @moduledoc false

  def supported?(attrs),
    do:
      not Map.has_key?(attrs, "tag_ids") or
        (is_list(attrs["tag_ids"]) and
           Enum.all?(
             attrs["tag_ids"],
             &(is_nil(&1) or is_integer(&1) or (is_binary(&1) and &1 =~ ~r/\A\d*\z/))
           ))

  def save(repo, action, owner, id, attrs, stamp) do
    if Map.has_key?(attrs, "tag_ids") do
      ids =
        attrs["tag_ids"]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.map(fn id -> if is_integer(id), do: id, else: String.to_integer(id) end)
        |> Enum.uniq()

      repo.transaction(fn ->
        selected =
          repo.query!(
            "SELECT id FROM tags WHERE user_id=$1 AND id=ANY($2) ORDER BY id",
            [owner, ids],
            log: false
          ).rows
          |> List.flatten()

        if action == :update do
          repo.query!(
            "DELETE FROM taggings WHERE taggable_type='Place' AND taggable_id=$1 AND NOT (tag_id=ANY($2))",
            [id, selected],
            log: false
          )
        end

        existing =
          repo.query!(
            "SELECT tag_id FROM taggings WHERE taggable_type='Place' AND taggable_id=$1",
            [id],
            log: false
          ).rows
          |> List.flatten()

        for tag <- selected -- existing,
            do:
              repo.query!(
                "INSERT INTO taggings (tag_id,taggable_type,taggable_id,created_at,updated_at) VALUES ($1,'Place',$2,$3,$3)",
                [tag, id, stamp],
                log: false
              )
      end)
      |> case do
        {:ok, _} -> :ok
        {:error, reason} -> raise "place tags phase: #{inspect(reason)}"
      end
    else
      :ok
    end
  end
end
