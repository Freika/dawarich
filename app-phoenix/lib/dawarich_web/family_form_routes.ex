defmodule DawarichWeb.FamilyFormRoutes do
  @moduledoc false
  alias DawarichWeb.FamilyActions
  def init(opts), do: opts

  def call(%{method: "GET", request_path: "/family/invitations/new"} = conn, _opts),
    do: DawarichWeb.FamilyInvitationPage.call(conn, :new)

  def call(conn, _opts) do
    conn = FamilyActions.prepare(conn)

    if conn.halted do
      conn
    else
      path = Regex.replace(~r/\.[^\/]+$/, conn.request_path, "")

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

        {"POST", "/family"} ->
          FamilyActions.call(conn, :create)

        {verb, "/family"} when verb in ["PATCH", "PUT"] ->
          FamilyActions.call(conn, :update)

        _other ->
          conn |> Plug.Conn.send_resp(404, "") |> Plug.Conn.halt()
      end
    end
  end

  defmacro routes do
    quote do
      get "/family/invitations/new", DawarichWeb.FamilyInvitationPage, :new
      post "/family/invitations", DawarichWeb.FamilyInvitationActions, :create
      delete "/family/invitations/:id", DawarichWeb.FamilyInvitationActions, :destroy
      post "/family/memberships", DawarichWeb.FamilyInvitationActions, :accept
      post "/family", DawarichWeb.FamilyActions, :create
      patch "/family", DawarichWeb.FamilyActions, :update
      put "/family", DawarichWeb.FamilyActions, :update
      delete "/family", DawarichWeb.FamilyActions, :destroy
      delete "/family/members/:id", DawarichWeb.FamilyMembershipActions, :destroy
    end
  end
end
