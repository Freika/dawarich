defmodule Dawarich.Achievements.Pages do
  @moduledoc false
  alias Dawarich.Accounts.DataAccess
  alias Dawarich.Achievements.{Collection, PublicCard, UiText}

  def load(subject, params, opts \\ []) do
    with {:ok, scope} <- DataAccess.admit(subject, settings: true),
         {:ok, params} <- normalize(params),
         [[state]] <-
           Dawarich.Repo.query!(
             "SELECT COALESCE((SELECT state FROM achievement_progresses WHERE user_id=$1 AND achievement_key='exploration'), '{}'::jsonb)",
             [scope.user.id], log: false).rows,
         true <- PublicCard.supported_state?(state),
         {:ok, view} <-
           Collection.load(Dawarich.Repo, scope.user.id, params, context(scope, opts)) do
      cards = if view[:set], do: [view.set], else: view.sets ++ view.orphans
      keys = cards |> Enum.filter(& &1["celebrate"]) |> Enum.map(& &1["key"])

      {:ok,
       %{
         view: view,
         query: params,
         celebrations: keys,
         threshold:
           Dawarich.RubyInteger.to_i(scope.user.settings["min_minutes_spent_in_city"] || 60)
       }}
    else
      false -> {:error, :unsupported}
      other -> other
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def normalize(params) when is_map(params) do
    if Enum.all?(~w(key q status page), &(is_nil(params[&1]) or is_binary(params[&1]))) do
      {:ok,
       params
       |> Map.take(~w(key q status page))
       |> Map.put("q", UiText.query(params["q"] || ""))
       |> Map.put("page", params["page"] || "1")}
    else
      {:error, :invalid_input}
    end
  end

  def normalize(_), do: {:error, :invalid_input}

  def context(scope, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    %{locale: scope.locale, settings: scope.user.settings, now: now, acknowledge: false}
  end
end
