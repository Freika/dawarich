defmodule Dawarich.UserData.Restore.Imports do
  @moduledoc false
  alias Dawarich.UserData.Restore.{Batch, Files}
  alias Dawarich.Ingest.Ruby
  alias Dawarich.Imports.NormalCast.Text

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
    name = Text.cast(data["name"])
    identity = Batch.row!(repo, "imports", Map.take(data, ~w(name source created_at)), context)

    existing =
      repo.query!(
        "SELECT id FROM imports WHERE user_id=$1 AND name IS NOT DISTINCT FROM $2 AND source IS NOT DISTINCT FROM $3 AND created_at IS NOT DISTINCT FROM $4::text::timestamp LIMIT 1",
        [user, name, identity["source"], identity["created_at"]],
        log: false
      ).rows

    if existing == [] do
      row =
        data
        |> Files.attributes()
        |> Map.drop(~w(user updated_at skip_background_processing))
        |> Map.put("user_id", user)
        |> Map.put("updated_at", context.now)

      row = if row["status"] == "processing", do: Map.put(row, "status", "failed"), else: row

      row =
        if row["additional_data_extraction_status"] in ~w(pending running),
          do: Map.put(row, "additional_data_extraction_status", "not_attempted"),
          else: row

      row =
        row
        |> Map.update("created_at", context.now, &if(Ruby.blank?(&1), do: context.now, else: &1))
        |> then(&Batch.row!(repo, "imports", &1, context))

      if Ruby.present?(name) and
           repo.query!(
             "SELECT id FROM imports WHERE user_id=$1 AND name=$2 LIMIT 1",
             [user, name],
             log: false
           ).rows == [] and not trial_limit?(repo, user, row) do
        supported = row["source"] in [0, 3, 4, 13]
        status = Map.get(row, "additional_data_extraction_status", 0)

        status =
          cond do
            supported and status == 5 -> 0
            not supported and status == 0 -> 5
            true -> status
          end

        row = Map.put(row, "additional_data_extraction_status", status)

        row =
          if row["status"] == 1, do: Map.put(row, "processing_started_at", context.now), else: row

        id = Batch.create_record!(repo, "imports", row, context)
        Files.restore(repo, "Import", id, data, directory, context)
      end
    end
  end

  defp restore(_, _, _, _, _), do: nil

  defp trial_limit?(repo, user, data) do
    if data["demo"] in [nil, false] do
      [[status, source]] =
        repo.query!("SELECT status,subscription_source FROM users WHERE id=$1", [user],
          log: false
        ).rows

      status == 2 and source in [nil, 0] and
        repo.query!("SELECT id FROM imports WHERE user_id=$1 AND demo=false LIMIT 5", [user],
          log: false
        ).num_rows >= 5
    else
      false
    end
  end
end
