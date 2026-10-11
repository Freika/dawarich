defmodule DawarichWeb.StatsRequest do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias DawarichWeb.{A8FormDecode, Locale, RailsForm, RequireUser}
  alias DawarichWeb.Api.Body

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = assign(conn, :api_tag, "stats")

    with {:ok, conn, params} <- A8FormDecode.params(conn, []),
         true <- method?(conn, params) do
      params = Map.delete(params, "_method")

      conn =
        conn
        |> assign(:api_params, params)
        |> assign(:api_query, %{})
        |> assign(
          :locale,
          Locale.resolve(nil, conn.assigns.current_user, conn.assigns.rails_session)
        )
        |> RequireUser.call([])

      if conn.halted, do: conn, else: RailsForm.call(conn, [])
    else
      _ -> Body.replay(conn, "stats request envelope")
    end
  end

  defp method?(%{method: "POST"}, %{"_method" => method}), do: String.upcase(method) == "PUT"
  defp method?(%{method: "PUT"}, params), do: not Map.has_key?(params, "_method")
  defp method?(_, _), do: false
end
