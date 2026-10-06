defmodule DawarichWeb.FamilyFormRoutes do
  @moduledoc false
  alias DawarichWeb.FamilyActions
  def init(opts), do: opts

  def call(%{method: "GET"} = conn, _opts) do
    if path(conn) == "/family/invitations/new",
      do: DawarichWeb.FamilyInvitationPage.call(conn, :new),
      else: conn |> Plug.Conn.send_resp(404, "") |> Plug.Conn.halt()
  end

  def call(conn, _opts) do
    conn = FamilyActions.prepare(conn)

    if conn.halted do
      conn
    else
      path = path(conn)

      case {conn.method, path} do
        {"DELETE", "/family"} ->
          FamilyActions.call(conn, :destroy)

        {"DELETE", "/family/members/" <> id} ->
          DawarichWeb.FamilyMembershipActions.call(%{conn | path_params: %{"id" => id}}, :destroy)

        {"POST", "/family/invitations"} ->
          DawarichWeb.FamilyInvitationActions.call(conn, :create)

        {"DELETE", "/family/invitations/" <> token} ->
          DawarichWeb.FamilyInvitationActions.call(
            %{conn | path_params: %{"id" => token}},
            :destroy
          )

        {"POST", "/family/memberships"} ->
          DawarichWeb.FamilyInvitationActions.call(conn, :accept)

        {"POST", "/family/location_requests"} ->
          DawarichWeb.FamilyRequestActions.call(conn, :create)

        {"PATCH", "/family/location_requests/" <> rest} ->
          request_action(conn, rest)

        {"PATCH", "/family/location_sharing"} ->
          DawarichWeb.FamilySharingActions.call(conn, :update)

        {"POST", "/family"} ->
          FamilyActions.call(conn, :create)

        {verb, "/family"} when verb in ["PATCH", "PUT"] ->
          FamilyActions.call(conn, :update)

        _other ->
          conn |> Plug.Conn.send_resp(404, "") |> Plug.Conn.halt()
      end
    end
  end

  defp request_action(conn, rest) do
    case String.split(rest, "/") do
      [id, "accept"] ->
        DawarichWeb.FamilyRequestActions.call(%{conn | path_params: %{"id" => id}}, :accept)

      [id, "decline"] ->
        DawarichWeb.FamilyRequestActions.call(%{conn | path_params: %{"id" => id}}, :decline)

      _other ->
        conn |> Plug.Conn.send_resp(404, "") |> Plug.Conn.halt()
    end
  end

  defp path(conn), do: Regex.replace(~r/\.[^\/]+$/, conn.request_path, "")

  defmacro routes do
    paths = [
      {[:get], "/family/invitations/new"},
      {[:post], "/family/invitations"},
      {[:post, :delete], "/family/invitations/:id"},
      {[:post], "/family/memberships"},
      {[:post], "/family/location_requests"},
      {[:post, :patch], "/family/location_requests/:id/accept"},
      {[:post, :patch], "/family/location_requests/:id/decline"},
      {[:post, :patch], "/family/location_sharing"},
      {[:post, :patch, :put, :delete], "/family"},
      {[:post, :delete], "/family/members/:id"}
    ]

    routes =
      for {verbs, path} <- paths,
          verb <- verbs,
          suffix <-
            if(String.starts_with?(List.last(String.split(path, "/")), ":"),
              do: [""],
              else: ["", ".:format"]
            ) do
        quote do
          match unquote(verb), unquote(path <> suffix), DawarichWeb.FamilyFormRoutes, :dispatch,
            as: nil
        end
      end

    quote do
      (unquote_splicing(routes))
    end
  end
end
