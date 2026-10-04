defmodule DawarichWeb.AchievementActions.Gate do
  @moduledoc false
  alias Dawarich.Auth.Admission
  alias Dawarich.Achievements.{PublicCard, Registry}
  alias DawarichWeb.{AchievementContext, RailsAuth}

  @markers ~w(client aff via referral invitation_token pending_import_ticket dawarich_client)
  @headers ~w(turbo-frame x-http-method-override x-dawarich-client)
  @sharing ~r|\A/achievements/([a-z0-9_]+)/toggle_sharing\z|
  @seen ~r|\A/achievements/unlocks/([a-zA-Z0-9+_-]{1,40})/seen\z|

  def sharing?(conn, _params), do: eligible?(conn, :sharing)
  def next?(conn, _params), do: eligible?(conn, :next)
  def seen?(conn, _params), do: eligible?(conn, :seen)
  def dismiss?(conn, _params), do: eligible?(conn, :dismiss)

  def context(opts) do
    Keyword.get(opts, :context, %{})
    |> Map.put_new(:repo, Dawarich.Repo)
    |> Map.put_new_lazy(:clock, fn -> AchievementContext.clock() end)
  end

  def eligible?(conn, action, opts \\ []) do
    with {:ok, _} <- route(conn, action),
         :ok <- Admission.headers(conn.req_headers),
         false <- Enum.any?(conn.req_headers, fn {name, _} -> String.contains?(name, "_") end),
         true <- Enum.all?(@headers, &(Plug.Conn.get_req_header(conn, &1) == [])),
         {:ok, _, _} <- actor(conn, context(opts)) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def actor(conn, context) do
    opts = if context[:secret], do: [secret: context.secret], else: []
    conn = RailsAuth.call(conn, opts)
    session = conn.assigns.rails_session

    with %{"warden.user.user.key" => [[id], salt]} when is_integer(id) and is_binary(salt) <-
           session,
         %{id: ^id} = actor <- conn.assigns.current_user,
         false <- Enum.any?(@markers, &Map.has_key?(session, &1)) do
      {:ok, conn, actor}
    else
      _ -> :handoff
    end
  rescue
    _ -> :handoff
  end

  def route(%{method: method, request_path: path}, :sharing) when method in ~w(PATCH POST) do
    case Regex.run(@sharing, path) do
      [_, key] -> if Registry.find(key), do: {:ok, %{key: key}}, else: :handoff
      _ -> :handoff
    end
  end

  def route(%{method: "POST", request_path: "/achievements/unlocks/next"}, :next), do: {:ok, %{}}

  def route(%{method: "POST", request_path: "/achievements/unlocks/dismiss"}, :dismiss),
    do: {:ok, %{}}

  def route(%{method: "POST", request_path: path}, :seen) do
    case Regex.run(@seen, path) do
      [_, id] -> {:ok, %{id: id}}
      _ -> :handoff
    end
  end

  def route(_, _), do: :handoff

  def snapshot(actor, action, route, params, context) do
    context = pending(actor.id, action, context)

    with true <- PublicCard.supported_settings?(actor.settings, context.repo),
         true <- input?(action, params),
         {:ok, state} <- snapshot_state(actor.id, action, route, context) do
      {:ok,
       Map.merge(context, route) |> Map.put(:state, state) |> Map.put(:settings, actor.settings)}
    else
      _ -> :handoff
    end
  rescue
    _ -> :handoff
  end

  defp input?(:sharing, params),
    do: not Map.has_key?(params, "enabled") or params["enabled"] not in [nil, ""]

  defp input?(action, params) when action in [:next, :seen],
    do: is_nil(params["claim_token"]) or is_binary(params["claim_token"])

  defp input?(_, _), do: true

  defp pending(id, :next, context) do
    [[pending]] =
      query(
        context.repo,
        "SELECT EXISTS(SELECT 1 FROM achievement_unlock_events WHERE user_id=$1 AND seen_at IS NULL)",
        [id]
      )

    Map.put(context, :pending, pending)
  end

  defp pending(_, _, context), do: context
  defp snapshot_state(_, :next, _, %{pending: false}), do: {:ok, %{}}
  defp snapshot_state(id, action, route, context), do: state(id, action, route, context.repo)

  defp state(id, :sharing, %{key: key}, repo) do
    case query(
           repo,
           "SELECT state,sharing_enabled,sharing_uuid FROM achievement_progresses WHERE user_id=$1 AND achievement_key=$2",
           [id, key]
         ) do
      [] ->
        {:ok, %{}}

      [[state, enabled, uuid]] when is_boolean(enabled) and (is_nil(uuid) or is_binary(uuid)) ->
        {:ok, state}

      _ ->
        :handoff
    end
  end

  defp state(id, _action, _route, repo) do
    state =
      case query(
             repo,
             "SELECT state FROM achievement_progresses WHERE user_id=$1 AND achievement_key='exploration'",
             [id]
           ) do
        [[state]] -> state
        [] -> %{}
      end

    if PublicCard.supported_state?(state), do: {:ok, state}, else: :handoff
  end

  defp query(repo, sql, args), do: repo.query!(sql, args, log: false, prepare: :unnamed).rows
end
