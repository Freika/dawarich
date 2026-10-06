defmodule DawarichWeb.ShareManagementMethod do
  @moduledoc false
  alias DawarichWeb.Api.Body

  def action(conn, route_action) do
    case {route_action, effective_method(conn)} do
      {:create, "DELETE"} -> {:ok, :destroy}
      {action, "POST"} when action in [:create, :regenerate, :regenerate_phrase] -> {:ok, action}
      {:destroy, "DELETE"} -> {:ok, :destroy}
      {:revoke, "PATCH"} -> {:ok, :revoke}
      _ -> {:replay, "share management method"}
    end
  end

  defp effective_method(conn) do
    override = conn.assigns.api_params["_method"]

    if conn.method == "POST" and Body.kind(conn) == :form and is_binary(override),
      do: String.upcase(override),
      else: conn.method
  end
end
