defmodule DawarichWeb.TimelineShareActions do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn, only: [get_req_header: 2]
  alias Dawarich.ShareManagement.Read

  alias DawarichWeb.{
    LayoutAssigns,
    RailsAuth,
    RequireUser,
    ShareManagementDocument,
    ShareManagementForm,
    ShareManagementPage
  }

  alias DawarichWeb.Api.Body
  def init(action), do: action

  def native?(conn, _params) do
    conn.method in ~w(GET HEAD POST PATCH DELETE) and
      (Dawarich.Standalone.enabled?() or LayoutAssigns.self_hosted?()) and
      get_req_header(conn, "turbo-frame") in [[], ["share-link-modal"]] and
      get_req_header(conn, "x-dawarich-client") == []
  end

  def call(conn, action) do
    conn = conn |> RailsAuth.call([]) |> RequireUser.call([])

    if conn.halted do
      conn
    else
      if native?(conn, conn.path_params),
        do: perform(conn, action),
        else: Body.replay(conn, "timeline share transport")
    end
  end

  defp perform(conn, :new) do
    conn = LayoutAssigns.call(conn, [])

    case Read.timeline(conn.assigns.current_user, conn.query_params, conn.assigns.now) do
      {:ok, page} ->
        content =
          ShareManagementDocument.frame(%{
            __changed__: nil,
            page: page,
            ctx: ShareManagementPage.context(conn),
            type: "timeline"
          })

        ShareManagementPage.respond(conn, content)

      result ->
        ShareManagementForm.respond(conn, {"timeline", :new}, %{}, result)
    end
  end

  defp perform(conn, action) do
    case ShareManagementForm.admission(conn) do
      :ok ->
        conn
        |> ShareManagementForm.call({"timeline", action})

      {:replay, reason} ->
        Body.replay(conn, reason)
    end
  end
end
