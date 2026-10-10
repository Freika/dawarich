defmodule Dawarich.UserData.Restore.Exports do
  @moduledoc false
  alias Dawarich.UserData.Restore.{Batch, Files}
  alias Dawarich.Ingest.Ruby

  def call(repo, user, data, directory, context) when is_list(data) do
    Enum.reduce(data, [0, 0], fn row, [created, files] ->
      case restore(repo, user, row, directory, context) do
        nil -> [created, files]
        file -> [created + 1, files + if(file, do: 1, else: 0)]
      end
    end)
  end

  def call(_, _, _, _, _), do: [0, 0]

  defp restore(repo, user, data, directory, context) when is_map(data) do
    if Enum.all?(~w(name file_format status), &Ruby.present?(data[&1])) do
      row = data |> Files.attributes() |> Map.drop(~w(user)) |> Map.put("user_id", user)

      row =
        Enum.reduce(~w(created_at updated_at), row, fn name, row ->
          Map.update(row, name, context.now, &if(Ruby.blank?(&1), do: context.now, else: &1))
        end)

      row = Batch.row!(repo, "exports", row, context)

      if repo.query!(
           "SELECT id FROM exports WHERE user_id=$1 AND name=$2 AND created_at=$3::text::timestamp LIMIT 1",
           [user, row["name"], row["created_at"]],
           log: false
         ).rows == [] do
        row =
          if row["status"] == 1, do: Map.put(row, "processing_started_at", context.now), else: row

        id = Batch.create_record!(repo, "exports", row, context)

        if row["status"] == 0 and Map.get(row, "file_type", 0) == 0 and row["file_format"] != 2 do
          Dawarich.Imports.Fence.run(context, fn ->
            [[settings]] =
              repo.query!("SELECT settings FROM users WHERE id=$1", [user], log: false).rows

            Dawarich.PointExports.enqueue_created(
              repo,
              id,
              %{id: user, settings: settings},
              context.locale,
              context.now
            )
          end)
        end

        Files.restore(repo, "Export", id, data, directory, context)
      end
    end
  rescue
    _ in [ArgumentError, KeyError] -> nil
  end

  defp restore(_, _, _, _, _), do: nil
end
