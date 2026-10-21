defmodule Dawarich.Visits.Commands do
  @moduledoc false
  alias Dawarich.Accounts.DataAccess

  alias Dawarich.Visits.{
    WebUpdate,
    WebDelete,
    WebBulk,
    WebMerge,
    WebScope,
    WebEffects,
    CacheGeneration
  }

  alias Dawarich.Repo

  def update(scope, id, attrs, opts \\ []), do: command(scope, :update, {id, attrs}, opts)
  def delete(scope, id, opts \\ []), do: command(scope, :delete, id, opts)
  def bulk_update(scope, params, opts \\ []), do: command(scope, :bulk_update, params, opts)
  def bulk_delete(scope, params, opts \\ []), do: command(scope, :bulk_delete, params, opts)
  def merge(scope, ids, opts \\ []), do: command(scope, :merge, ids, opts)

  defp command(scope, action, input, opts) do
    with {:ok, fresh} <- DataAccess.admit(scope, settings: true),
         :ok <- shape(action, input) do
      case Repo.transaction(fn ->
             Repo.query!("SELECT id FROM users WHERE id=$1 FOR UPDATE", [fresh.user.id],
               log: false
             )

             context = %{
               now: Keyword.get(opts, :now, DateTime.utc_now()),
               self_hosted:
                 Keyword.get(
                   opts,
                   :self_hosted,
                   Dawarich.ReleaseMigration.self_hosted?(System.get_env())
                 )
             }

             with {:ok, fresh} <- DataAccess.admit(scope, settings: true),
                  {:ok, result} <- execute(action, fresh.user, input, context) do
               projection(action, fresh.user, result)
             else
               {:error, reason} ->
                 Repo.rollback(reason)

               {:replay, reason}
               when reason in ["Postgrex.Error", "DBConnection.ConnectionError"] ->
                 Repo.rollback(:unavailable)

               _ ->
                 Repo.rollback(:invalid_input)
             end
           end) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp execute(:update, user, {id, attrs}, context),
    do: WebUpdate.run(Repo, user, id, attrs, context)

  defp execute(:delete, user, id, context), do: WebDelete.run(Repo, user, id, %{}, context)

  defp execute(:bulk_update, user, params, context),
    do: WebBulk.run(Repo, :update, user, params, context)

  defp execute(:bulk_delete, user, params, context),
    do: WebBulk.run(Repo, :destroy, user, params, context)

  defp execute(:merge, user, ids, context), do: WebMerge.run(Repo, user, ids, context)

  defp shape(:merge, ids), do: selection(ids)

  defp shape(action, params) when action in [:bulk_update, :bulk_delete] and is_map(params),
    do: selection(params["visit_ids"])

  defp shape(:update, {id, attrs}) when is_map(attrs), do: single(id)
  defp shape(:delete, id), do: single(id)
  defp shape(_, _), do: {:error, :invalid_input}

  defp single(id) do
    case WebEffects.single_id(id) do
      {:ok, id} when id <= 9_223_372_036_854_775_807 -> :ok
      _ -> {:error, :invalid_input}
    end
  end

  defp selection(ids) when is_list(ids) and length(ids) > 500, do: {:error, :too_many}

  defp selection(ids) do
    case WebScope.ids(ids) do
      {:ok, parsed} ->
        if(Enum.all?(parsed, &(&1 > 0 and &1 <= 9_223_372_036_854_775_807)),
          do: :ok,
          else: {:error, :invalid_input}
        )

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, :invalid_input}
    end
  end

  defp projection(action, user, result) do
    rows =
      case action do
        action when action in [:update, :delete] -> [result.old, result.visit]
        :merge -> result.rows ++ [result.visit]
        _ -> result.rows
      end

    ids =
      case action do
        :merge -> [result.visit["id"] | result.source_ids]
        action when action in [:update, :delete] -> [result.visit["id"]]
        _ -> result.ids
      end

    {setting, months} = CacheGeneration.months(Repo, user, WebEffects.stamps(rows))
    keys = Enum.map(months, &"timeline_visit_month/#{user.id}/#{&1}/#{setting}")

    revisions =
      Repo.query!("SELECT key,token FROM phoenix.epochs WHERE key=ANY($1::text[])", [keys],
        log: false
      ).rows
      |> Map.new(fn [key, revision] -> {Enum.at(String.split(key, "/"), 2), revision} end)

    %{
      ids: ids,
      days: Enum.map(WebEffects.dates(Repo, rows, result.zone), &Date.to_iso8601/1),
      month_revisions: revisions,
      notice: notice(action, result),
      bindings: if(action in [:bulk_update, :bulk_delete], do: %{count: result.count}, else: %{})
    }
  end

  defp notice(:update, result),
    do:
      "controllers.visits.visit_updated." <>
        Enum.at(~w(suggested confirmed declined), result.visit["status"])

  defp notice(:delete, _), do: "controllers.visits.visit_removed"
  defp notice(:merge, _), do: "controllers.visits.visits_merged"
  defp notice(:bulk_update, result), do: "controllers.visits.bulk_updated." <> result.status
  defp notice(:bulk_delete, _), do: "controllers.visits.bulk_removed"
end
