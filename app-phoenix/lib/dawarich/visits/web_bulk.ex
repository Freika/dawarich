defmodule Dawarich.Visits.WebBulk do
  @moduledoc false
  alias Dawarich.RailsEffects
  alias Dawarich.Visits.{WebEffects, WebScope}
  @statuses %{"suggested" => 0, "confirmed" => 1, "declined" => 2}

  def run(repo, action, user, %{} = params, context) when action in [:update, :destroy] do
    with :ok <- source(params["source_status"]),
         {:ok, ids} <- WebScope.ids(params["visit_ids"]),
         {:ok, zone} <- WebEffects.zone(repo, user, context),
         {:ok, bounds} <- bounds(repo, params["date"], zone) do
      WebEffects.transact(repo, fn ->
        with {:ok, selected} <- select(repo, action, user, ids, params, bounds, context),
             :ok <- validate(action, selected, params["status"]) do
          write(repo, action, selected, params["status"], context.now)
          RailsEffects.visit_months(repo, user.id, WebEffects.stamps(selected))

          if action == :destroy or params["status"] == "declined" do
            RailsEffects.orphan_places(
              repo,
              user.id,
              selected |> Enum.map(& &1["place_id"]) |> Enum.reject(&is_nil/1)
            )
          end

          {:ok,
           %{
             ids: Enum.map(selected, & &1["id"]),
             count: length(selected),
             rows: selected,
             dates: WebEffects.dates(repo, selected, zone),
             zone: zone,
             date: params["date"],
             source_status: params["source_status"] || "suggested",
             status: params["status"]
           }}
        end
      end)
    end
  end

  def run(_repo, _action, _user, _params, _context), do: {:replay, "visit bulk shape"}

  defp source(value) when value in [nil, "suggested"], do: :ok
  defp source(""), do: {:replay, "blank visit source"}
  defp source(value) when is_binary(value), do: {:error, :unsupported_source_status}
  defp source(_value), do: {:replay, "visit source shape"}

  defp bounds(_repo, value, _zone) when value in [nil, ""], do: {:ok, {nil, nil}}
  defp bounds(repo, value, zone), do: WebScope.day_bounds(zone, value, repo)

  defp select(repo, _action, user, [_ | _] = ids, _params, _bounds, context),
    do: WebScope.load(repo, user, ids, context.now, context.self_hosted)

  defp select(repo, action, user, [], params, {first, last}, context) do
    if action == :destroy and (is_nil(first) or params["source_status"] != "suggested") do
      {:error, :select_visit_to_delete}
    else
      with {:ok, cutoff} <- WebScope.cutoff(repo, user, context.now, context.self_hosted) do
        ids =
          repo.query!(
            "SELECT id FROM visits WHERE user_id=$1 AND deleted_at IS NULL AND status=0 AND ($2::timestamp IS NULL OR started_at >= $2) AND ($3::timestamp IS NULL OR started_at >= $3 AND started_at < $4) ORDER BY id LIMIT 501 FOR UPDATE",
            [user.id, cutoff, first, last],
            log: false
          ).rows
          |> Enum.map(&hd/1)

        cond do
          length(ids) > 500 -> {:error, :too_many}
          ids == [] and action == :destroy -> {:error, :no_matching_visits}
          true -> WebScope.load(repo, user, ids, context.now, context.self_hosted)
        end
      end
    end
  end

  defp validate(:update, rows, status) do
    cond do
      rows == [] -> {:error, :failed_to_update_visits}
      is_map_key(@statuses, status) -> :ok
      is_binary(status) or is_nil(status) -> {:error, :failed_to_update_visits}
      true -> {:replay, "visit status shape"}
    end
  end

  defp validate(:destroy, _rows, _status), do: :ok

  defp write(repo, :update, rows, status, _now),
    do:
      repo.query!(
        "UPDATE visits SET status=$2 WHERE id=ANY($1)",
        [Enum.map(rows, & &1["id"]), @statuses[status]],
        log: false
      )

  defp write(repo, :destroy, rows, _status, now),
    do:
      repo.query!(
        "UPDATE visits SET deleted_at=$2 WHERE id=ANY($1)",
        [Enum.map(rows, & &1["id"]), DateTime.to_naive(now)],
        log: false
      )
end
