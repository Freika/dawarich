defmodule DawarichWeb.Api.ImportsController do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Imports.Api
  alias DawarichWeb.Api.Respond

  def init(action), do: action

  def call(conn, action) do
    params = Map.merge(conn.assigns.api_params, conn.path_params)
    user = conn.assigns.api_user
    ctx = Api.context(conn)

    result =
      case action do
        :index -> Api.index(Dawarich.Repo, user.id, params)
        :show -> Api.show(Dawarich.Repo, user.id, params["id"])
        :create -> Api.create(Dawarich.Repo, user, params, ctx)
      end

    case result do
      {:ok, rows, %{current_page: page, total_pages: pages}} ->
        conn
        |> put_resp_header("x-current-page", to_string(page))
        |> put_resp_header("x-total-pages", to_string(pages))
        |> Respond.json(200, Api.term(rows))

      {:ok, record} ->
        Respond.json(conn, 200, Api.term(record))

      {:ok, status, body} ->
        Respond.json(conn, status, Api.term(body))

      {:error, status, body} ->
        Respond.json(conn, status, body)
    end
  rescue
    _ ->
      Respond.json(conn, 500, %{
        "error" =>
          Dawarich.I18n.en!(
            "controllers.api.v1.imports.an_error_occurred_while_processing_the_import"
          )
      })
  end
end
