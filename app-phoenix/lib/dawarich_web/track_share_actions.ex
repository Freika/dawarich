defmodule DawarichWeb.TrackShareActions do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn, only: [get_req_header: 2, assign: 3]
  alias Dawarich.ShareManagement.Read

  alias DawarichWeb.{
    LayoutAssigns,
    Locale,
    RailsAuth,
    RequireUser,
    ShareManagementDocument,
    ShareManagementForm,
    ShareManagementPage
  }

  alias DawarichWeb.Api.Body
  def init(action), do: action

  def native?(conn, params) do
    conn.method in ~w(GET HEAD POST PATCH DELETE) and
      (Dawarich.Standalone.enabled?() or LayoutAssigns.self_hosted?()) and
      is_binary(params["track_id"]) and params["track_id"] =~ ~r/\A\d{1,18}\z/ and
      get_req_header(conn, "turbo-frame") in [[], ["share-link-modal"]] and
      get_req_header(conn, "x-dawarich-client") == []
  end

  def call(conn, action) do
    conn = conn |> RailsAuth.call([]) |> RequireUser.call([])

    if conn.halted do
      conn
    else
      conn =
        assign(
          conn,
          :locale,
          conn.assigns[:locale] ||
            Locale.resolve(nil, conn.assigns.current_user, conn.assigns.rails_session)
        )

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
           conn.assigns.now,
           conn.assigns.locale
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
        |> ShareManagementForm.call({"track", action})

      {:replay, reason} ->
        Body.replay(conn, reason)
    end
  end
end
