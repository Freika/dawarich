defmodule DawarichWeb.FamilyGate do
  @moduledoc false

  alias Dawarich.{Accounts, FamilyPage}

  def init(opts), do: opts

  def call(conn, _opts) do
    action = action(conn)

    if action do
      case FamilyPage.read(Accounts.get(conn.assigns.current_user.id), action,
             now: conn.assigns.now,
             self_hosted: conn.assigns.self_hosted
           ) do
        {:redirect, path, reason} -> redirect(conn, path, reason)
        {:error, 404} -> raise DawarichWeb.NotFoundError
        :rails -> conn |> Plug.Conn.send_resp(500, "") |> Plug.Conn.halt()
        _other -> conn
      end
    else
      conn
    end
  rescue
    ArgumentError -> conn |> Plug.Conn.send_resp(500, "") |> Plug.Conn.halt()
  end

  def on_mount(:default, _params, _session, socket) do
    {:cont, Phoenix.LiveView.attach_hook(socket, :family_access, :handle_event, &refresh/3)}
  end

  def refresh(_event, _params, socket) do
    user = Accounts.get(socket.assigns.current_user.id)
    action = action(%{request_path: socket.assigns.request_path})

    result =
      if user && action do
        FamilyPage.read(user, action,
          now: DateTime.utc_now(),
          self_hosted: socket.assigns.self_hosted
        )
      else
        {:redirect, "/users/sign_in", nil}
      end

    case result do
      {:ok, page} ->
        {:cont, Phoenix.Component.assign(socket, current_user: user, page: page)}

      {:redirect, path, _reason} ->
        socket = Phoenix.Component.assign(socket, :page, nil)
        {:halt, Phoenix.LiveView.redirect(socket, to: path)}

      _other ->
        socket = Phoenix.Component.assign(socket, :page, nil)
        {:halt, Phoenix.LiveView.redirect(socket, to: socket.assigns.request_path)}
    end
  end

  defp redirect(conn, path, reason) do
    key =
      case reason do
        :not_authorized ->
          "controllers.application.you_are_not_authorized_to_perform_this_action"

        :feature_unavailable ->
          "controllers.application.family_plan_required"

        :not_in_family ->
          if String.starts_with?(conn.request_path, "/family/location_requests/"),
            do: "controllers.family.location_requests.you_must_be_part_of_a_family",
            else: "controllers.families.you_are_not_in_a_family"

        :not_request_target ->
          "controllers.family.location_requests.you_are_not_authorized_to_view_this_request"

        nil ->
          nil
      end

    conn =
      if key,
        do:
          DawarichWeb.RailsSession.stage(conn, %{
            "flash" => %{
              "discard" => [],
              "flashes" => %{
                "alert" =>
                  DawarichWeb.Translate.t(
                    if(reason == :not_authorized, do: "en", else: conn.assigns.locale),
                    key,
                    %{}
                  )
              }
            }
          }),
        else: conn

    path = if reason == :not_authorized, do: referer(conn) || path, else: path

    conn
    |> Plug.Conn.put_resp_header("location", DawarichWeb.RequestURL.base(conn) <> path)
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(
      if(reason in [:not_authorized, :feature_unavailable], do: 303, else: 302),
      ""
    )
    |> Plug.Conn.halt()
  end

  defp referer(conn) do
    with [header] <- Plug.Conn.get_req_header(conn, "referer"),
         %URI{path: path} = uri <- URI.parse(header),
         true <-
           uri.scheme == URI.parse(DawarichWeb.RequestURL.base(conn)).scheme and
             uri.host == conn.host,
         true <-
           is_binary(path) and String.starts_with?(path, "/") and
             not String.starts_with?(path, "//") do
      path <> if(uri.query, do: "?" <> uri.query, else: "")
    else
      _other -> nil
    end
  end

  def show?(conn, _params), do: open?(conn, :show)
  def new?(conn, _params), do: open?(conn, :new)
  def edit?(conn, _params), do: open?(conn, :edit)
  def invitations?(conn, _params), do: open?(conn, :invitations)
  def request?(conn, %{"id" => id}), do: open?(conn, {:request, String.to_integer(id)})

  defp action(%{request_path: "/family/location_requests/" <> id}),
    do: {:request, String.to_integer(id)}

  defp action(conn),
    do:
      %{
        "/family" => :show,
        "/family/new" => :new,
        "/family/edit" => :edit,
        "/family/invitations" => :invitations
      }[conn.request_path]

  def open?(conn, action) do
    session_supported?(conn) and not is_nil(action)
  end

  def session_supported?(conn) do
    query = Plug.Conn.Query.decode(conn.query_string)

    Plug.Conn.get_req_header(conn, "x-dawarich-client") == [] and
      not Enum.any?(~w(client aff via), &Map.has_key?(query, &1)) and
      not DawarichWeb.RailsProxy.Headers.body?(conn)
  end
end
