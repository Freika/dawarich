defmodule Dawarich.VisitsApi.BulkUpdate do
  @moduledoc false

  alias Dawarich.{I18n, Jobs, RailsEffects, RubyInteger}

  @statuses %{"suggested" => 0, "confirmed" => 1, "declined" => 2}

  def call(owner, ids, status, repo \\ Jobs.repo()) do
    with :ok <- validate(ids, status),
         {:ok, ids} <- ids(ids) do
      case repo.transaction(fn -> update(repo, owner, ids, status) end) do
        {:ok, result} -> result
        {:error, result} -> result
      end
    end
  end

  defp validate(ids, _status) when ids in [nil, []], do: error("none_selected")

  defp validate(_ids, status),
    do: if(Map.has_key?(@statuses, status), do: :ok, else: error("invalid_status"))

  defp ids(ids) when is_list(ids) do
    if Enum.all?(ids, &(is_integer(&1) || is_binary(&1))),
      do:
        {:ok, Enum.map(ids, fn id -> if is_integer(id), do: id, else: RubyInteger.to_i(id) end)},
      else: {:replay, "visit bulk id shape"}
  end

  defp ids(_), do: {:replay, "visit bulk root shape"}

  defp update(repo, owner, ids, status) do
    selected =
      repo.query!(
        "SELECT id,place_id FROM visits WHERE user_id=$1 AND id=ANY($2) AND deleted_at IS NULL AND status!=2 ORDER BY id",
        [owner, ids]
      ).rows

    if selected == [] do
      error("none_found")
    else
      ids = Enum.map(selected, &hd/1)

      %{num_rows: count, rows: stamps} =
        repo.query!(
          "UPDATE visits SET status=$3 WHERE user_id=$1 AND id=ANY($2) AND deleted_at IS NULL AND status!=2 RETURNING started_at",
          [
            owner,
            ids,
            Map.fetch!(@statuses, status)
          ]
        )

      if status == "declined",
        do:
          RailsEffects.orphan_places(
            repo,
            owner,
            selected |> Enum.map(&List.last/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()
          )

      RailsEffects.visit_months(
        repo,
        owner,
        Enum.map(stamps, fn [stamp] -> DateTime.from_naive!(stamp, "Etc/UTC") end)
      )

      {:ok, count}
    end
  end

  defp error(key), do: {:error, 422, I18n.en!("services.visits.bulk_update." <> key)}
end
