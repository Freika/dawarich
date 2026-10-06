defmodule DawarichWeb.FamilyFormRoutes do
  @moduledoc false
  alias DawarichWeb.FamilyActions
  def init(opts), do: opts

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
      post "/family", DawarichWeb.FamilyActions, :create
      patch "/family", DawarichWeb.FamilyActions, :update
      put "/family", DawarichWeb.FamilyActions, :update
      delete "/family", DawarichWeb.FamilyActions, :destroy
      delete "/family/members/:id", DawarichWeb.FamilyMembershipActions, :destroy
    end
  end
end
