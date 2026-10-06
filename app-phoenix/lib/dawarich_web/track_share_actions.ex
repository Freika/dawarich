defmodule DawarichWeb.TrackShareActions do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
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

  def native?(conn, params) do
    conn.method in ~w(GET HEAD POST PATCH DELETE) and LayoutAssigns.self_hosted?() and
      is_binary(params["track_id"]) and params["track_id"] =~ ~r/\A\d{1,18}\z/ and
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
        else: Body.replay(conn, "track share transport")
    end
  end

  defp perform(conn, :new) do
    conn = LayoutAssigns.call(conn, [])

    case Read.track(
           conn.assigns.current_user,
           String.to_integer(conn.path_params["track_id"]),
           conn.assigns.now
         ) do
      {:ok, page} ->
        content =
          ShareManagementDocument.frame(%{
            __changed__: nil,
            page: page,
            ctx: ShareManagementPage.context(conn),
            type: "track"
          })

        ShareManagementPage.respond(conn, content)

      result ->
        ShareManagementForm.respond(conn, {"track", :new}, %{}, result)
    end
  end

  defp perform(conn, action) do
    case ShareManagementForm.admission(conn) do
      :ok ->
        conn
        |> assign(:api_params, Map.delete(conn.assigns.api_params, "_method"))
        |> ShareManagementForm.call({"track", action})

      {:replay, reason} ->
        Body.replay(conn, reason)
    end
  end
end
