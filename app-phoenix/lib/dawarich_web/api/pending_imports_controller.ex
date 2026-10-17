defmodule DawarichWeb.Api.PendingImportsController do
  @moduledoc false
  @behaviour Plug
  alias Dawarich.Imports.Api
  alias Dawarich.PendingImports.Intake
  alias DawarichWeb.Api.Respond

  @production Mix.env() == :prod

  def init(action), do: action

  def call(conn, :create) do
    ctx =
      Map.merge(
        %{
          origin: List.first(Plug.Conn.get_req_header(conn, "origin")),
          base_url: "#{conn.scheme}://#{conn.host}" <> port(conn),
          production?: @production
        },
        Api.context(conn)
      )

    case Intake.create(Dawarich.Repo, conn.assigns.api_params, ctx) do
      {_, status, nil} -> Respond.head(conn, status)
      {_, status, body} -> Respond.json(conn, status, body)
    end
  end

  defp port(%{scheme: :https, port: 443}), do: ""
  defp port(%{scheme: :http, port: 80}), do: ""
  defp port(conn), do: ":#{conn.port}"
end
