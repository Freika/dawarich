defmodule DawarichWeb.AchievementActions.Sharing do
  @moduledoc false
  @behaviour Plug
  alias Dawarich.Achievements.Sharing, as: Carrier
  alias DawarichWeb.{Locale}
  alias DawarichWeb.AchievementActions.{Request, Response}

  def init(opts), do: opts

  def call(%{assigns: %{achievement_action: {actor, params, context}}} = conn, _opts),
    do: execute(conn, actor, params, context)

  def call(conn, opts) do
    case Request.load(conn, :sharing, opts) do
      {:ok, conn, actor, params, context} ->
        if Response.supported?(conn),
          do: execute(conn, actor, params, context),
          else: handoff(conn, opts)

      {:handoff, %{halted: true} = conn} ->
        conn

      {:handoff, conn} ->
        handoff(conn, opts)
    end
  end

  defp execute(conn, actor, params, context) do
    case DawarichWeb.AchievementActions.Gate.fresh(conn, actor, context) do
      {:ok, conn, actor} -> execute_fresh(conn, actor, params, context)
      :error -> conn |> DawarichWeb.StandaloneError.respond("achievement_actor", 401)
    end
  end

  defp execute_fresh(conn, actor, params, context) do
    conn =
      if conn.assigns[:achievement_action],
        do: conn,
        else: Locale.call(%{conn | params: params}, [])

    case Carrier.call(context.repo, actor.id, context.key, params, context) do
      {:ok, result} -> Map.get(context, :respond, &Response.sharing/3).(conn, result, context)
      _ -> Response.terminal(conn)
    end
  rescue
    _ -> Response.terminal(conn)
  end

  defp handoff(conn, opts), do: DawarichWeb.AchievementActions.Gate.refuse(conn, opts)
end
