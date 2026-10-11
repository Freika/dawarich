defmodule Dawarich.Trips.Commands do
  @moduledoc false

  alias Dawarich.{Jobs, TripSettings}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Trips.{Pages, ShowCalculation, WebCommands, WebDelete, WebForm}
  alias Dawarich.Trips.{WebRecalculate, WebWrite}

  @notices %{
    create: "trip_was_successfully_created_data_is_being_calculated_in_the",
    update: "trip_was_successfully_updated",
    destroy: "trip_was_successfully_destroyed",
    queued: "recalculating_the_page_will_update_automatically_when_it_s_ready",
    cooldown: "already_recalculating_this_page_will_update_when_it_s_done",
    export: "trip_export_initiated_check_the_exports_page_when_it_s"
  }

  def create(scope, attrs, now, opts \\ [])

  def create(%Scope{user: user} = scope, attrs, now, opts) when is_map(attrs) do
    if WebForm.active?(user, now),
      do: write(scope, :create, nil, attrs, now, opts),
      else: {:error, :inactive}
  end

  def create(_scope, _attrs, _now, _opts), do: {:error, :unavailable}

  def update(scope, id, attrs, now, opts \\ [])

  def update(scope, id, attrs, now, opts) when is_map(attrs) do
    with {:ok, id} <- Pages.id(id), do: write(scope, :update, id, attrs, now, opts)
  end

  def update(_scope, _id, _attrs, _now, _opts), do: {:error, :unavailable}

  def delete(%Scope{user: user} = scope, id, now, opts \\ []) do
    with {:ok, id} <- Pages.id(id) do
      case WebDelete.run(repo(opts), user, id, Map.put(context(scope, now), :owner_scoped, true)) do
        {:ok, :deleted} -> {:ok, %{notice: notice(:destroy)}}
        other -> refusal(other)
      end
    end
  end

  def recalculate(%Scope{user: user} = scope, id, now, opts \\ []) do
    with {:ok, id} <- Pages.id(id),
         :ok <- owned(repo(opts), user, id) do
      if WebForm.active?(user, now) do
        case WebRecalculate.run(repo(opts), user, id, context(scope, now)) do
          {:ok, status} -> {:ok, %{status: status, notice: notice(status)}}
          other -> refusal(other)
        end
      else
        {:error, :inactive}
      end
    end
  end

  def request_export(%Scope{} = scope, id, format, opts \\ []) do
    with {:ok, id} <- Pages.id(id) do
      case Dawarich.Exports.request(scope, {:trip, id, format}, repo: repo(opts)) do
        {:ok, _} -> {:ok, %{notice: notice(:export)}}
        {:error, :invalid_format} -> {:error, :invalid_format}
        other -> refusal(other)
      end
    end
  end

  def ensure_calculated(%Scope{user: user}, id, now, opts \\ []) do
    with {:ok, id} <- Pages.id(id) do
      repo = repo(opts)

      repo.transaction(fn -> calculate_missing(repo, user, id, now) end)
      |> case do
        {:ok, {:ok, status}} -> {:ok, status}
        {:ok, other} -> refusal(other)
        other -> refusal(other)
      end
    end
  end

  def notice(key), do: "controllers.trips." <> Map.fetch!(@notices, key)

  defp calculate_missing(repo, user, id, now) do
    case repo.query!(
           "SELECT path IS NULL OR ST_IsEmpty(path), distance, visited_countries, started_at, source_identifier FROM trips WHERE id=$1 AND user_id=$2 FOR UPDATE",
           [id, user.id],
           log: false
         ).rows do
      [row] ->
        with {:ok, settings} <- TripSettings.read(Dawarich.UserSettings.get(user)) do
          if ShowCalculation.needed?(row, now),
            do: WebCommands.calculate!(repo, user, id, settings.unit, now),
            else: {:ok, :ready}
        end

      [] ->
        {:error, :not_found}
    end
  end

  defp write(%Scope{user: user} = scope, action, id, attrs, now, opts) do
    case WebWrite.run(repo(opts), action, user, id, attrs, context(scope, now)) do
      {:ok, row} -> {:ok, %{id: row.id, notice: notice(action)}}
      {:invalid, errors, values} -> {:invalid, errors, values}
      other -> refusal(other)
    end
  end

  defp owned(repo, user, id) do
    case repo.query!("SELECT 1 FROM trips WHERE id=$1 AND user_id=$2", [id, user.id], log: false).rows do
      [[1]] -> :ok
      [] -> {:error, :not_found}
    end
  end

  defp repo(opts), do: Keyword.get_lazy(opts, :repo, &Jobs.repo/0)

  defp context(%Scope{locale: locale}, now), do: %{now: now, locale: locale || "en"}

  defp refusal({:error, reason}) when reason in [:not_found, :attachment_refused],
    do: {:error, reason}

  defp refusal(_other), do: {:error, :unavailable}
end
