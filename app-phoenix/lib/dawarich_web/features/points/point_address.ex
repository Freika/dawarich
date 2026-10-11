defmodule DawarichWeb.PointAddress do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.{Navbar, PointList}
  alias DawarichWeb.{LayoutAssigns, Layouts, Locale, PointAddressFrame}

  def init(action), do: action

  def call(conn, _) do
    user = conn.assigns.current_user
    id = conn.path_info |> Enum.at(1) |> Dawarich.RubyInteger.to_i()

    case if(id in 1..9_223_372_036_854_775_807, do: PointList.address(user, id), else: :rails) do
      {:ok, point} ->
        locale = Locale.resolve(nil, user, conn.assigns.rails_session)
        inner = PointAddressFrame.frame(%{__changed__: nil, point: point, locale: locale})

        {conn, body} =
          if get_req_header(conn, "turbo-frame") == [] do
            conn = conn |> fetch_query_params() |> Locale.call([]) |> LayoutAssigns.call([])

            assigns =
              Map.merge(conn.assigns, %{
                __changed__: nil,
                flash: %{},
                page_title: nil,
                navbar:
                  Navbar.load(user, now: conn.assigns.now, self_hosted: conn.assigns.self_hosted),
                inner_content: inner
              })

            app = Layouts.app(assigns)
            {conn, Layouts.root(Map.put(assigns, :inner_content, app))}
          else
            {conn, inner}
          end

        conn
        |> put_resp_content_type("text/html")
        |> put_resp_header("vary", "Accept")
        |> send_resp(200, Phoenix.HTML.Safe.to_iodata(body))
        |> halt()

      :rails ->
        conn |> put_resp_content_type("text/html") |> send_resp(404, "") |> halt()
    end
  end
end
