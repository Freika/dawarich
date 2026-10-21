defmodule DawarichWeb.DigestRequest do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias DawarichWeb.{A8FormDecode, Locale, RailsForm, RequireUser}
  alias DawarichWeb.Api.Body
  def init(opts), do: opts

  def call(conn, _opts) do
    conn = assign(conn, :api_tag, "digests")

    with {:ok, conn, params} <- A8FormDecode.params(conn, []),
         true <- method?(conn, params) do
      query = Plug.Conn.Query.decode(conn.query_string)

      conn =
        conn
        |> assign(:api_params, Map.merge(Map.delete(params, "_method"), query))
        |> assign(:api_query, query)
        |> assign(
          :locale,
          Locale.resolve(nil, conn.assigns.current_user, conn.assigns.rails_session)
        )
        |> RequireUser.call([])

      if conn.halted, do: conn, else: RailsForm.call(conn, [])
    else
      _ -> Body.replay(conn, "digest request envelope")
    end
  end

  defp method?(%{method: "POST", path_info: ["digests"]}, %{"_method" => method})
       when is_binary(method),
       do: String.upcase(method) == "POST"

  defp method?(%{method: "POST", path_info: ["digests"]}, params),
    do: not Map.has_key?(params, "_method")

  defp method?(%{method: "POST"}, %{"_method" => method}) when is_binary(method),
    do: String.upcase(method) == "DELETE"

  defp method?(%{method: "DELETE"}, params), do: not Map.has_key?(params, "_method")
  defp method?(_, _), do: false
end
