defmodule DawarichWeb.ShareManagementStreams do
  @moduledoc false
  use DawarichWeb, :html
  import Plug.Conn
  alias Dawarich.ShareManagement.Read
  alias DawarichWeb.{ShareHub, ShareManagementForm, ShareManagementPage}

  def respond(conn, params, tab, errors, status) do
    conn = ShareManagementForm.presentation(conn)

    {:ok, hub} =
      Read.hub(conn.assigns.current_user, Map.put(params, "tab", tab), conn.assigns.now)

    hub = if is_nil(tab), do: %{hub | tab: ""}, else: hub

    content =
      streams(%{
        __changed__: nil,
        hub: hub,
        ctx: ShareManagementPage.context(conn),
        errors: errors
      })

    conn
    |> put_resp_content_type("text/vnd.turbo-stream.html")
    |> send_resp(status, Phoenix.HTML.Safe.to_iodata(content))
  end

  def streams(assigns) do
    ~H"""
    <turbo-stream action="update" target="share-hub-body">
      <template><ShareHub.body hub={@hub} ctx={@ctx} errors={@errors} /></template>
    </turbo-stream>
    <turbo-stream action="replace" target="live-share-indicator">
      <template><turbo-frame id="live-share-indicator" class="contents">
        <span
          :if={@hub.live}
          class="absolute -top-1 -right-1 w-2.5 h-2.5 bg-green-500 rounded-full animate-pulse ring-2 ring-base-100 pointer-events-none"
          data-testid="live-share-dot"
          title={t(@ctx.locale, "shared.map.share_indicator.live_location_is_being_shared", %{})}
        ></span>
      </turbo-frame></template>
    </turbo-stream>
    """
  end
end
