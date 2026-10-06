defmodule DawarichWeb.Api.TimelineController do
  @moduledoc false
  @behaviour Plug
  alias Dawarich.Timeline.Api
  alias DawarichWeb.Api.Respond
  def init(action), do: action

  def call(conn, :index) do
    case Api.fetch(conn.assigns.api_user, conn.assigns.api_params) do
      {:ok, result} -> Respond.json(conn, 200, Api.term(result))
      {:error, status, message} -> Respond.json(conn, status, {:object, [{"error", message}]})
      _ -> Respond.json(conn, 500, {:object, [{"error", "Timeline request failed"}]})
    end
  end
end
