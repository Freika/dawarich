defmodule DawarichWeb.AchievementActions.Sharing do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Achievements.Sharing, as: Carrier
  alias DawarichWeb.{Locale, RailsProxy}
  alias DawarichWeb.AchievementActions.{Request, Response}

  def init(opts), do: opts

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
    conn = Locale.call(%{conn | params: params}, [])

    case Carrier.call(context.repo, actor.id, context.key, params, context) do
      {:ok, result} -> Map.get(context, :respond, &Response.sharing/3).(conn, result, context)
      _ -> Response.terminal(conn)
    end
  rescue
    _ -> Response.terminal(conn)
  end

  defp handoff(conn, opts) do
    upstream =
      Keyword.get_lazy(opts, :upstream, fn ->
        Application.fetch_env!(:dawarich, :rails_upstream)
      end)

    conn |> RailsProxy.call(upstream) |> halt()
  end
end
