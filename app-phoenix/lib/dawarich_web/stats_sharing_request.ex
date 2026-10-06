defmodule DawarichWeb.StatsSharingRequest do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias DawarichWeb.{A8FormDecode, Locale, RailsForm, RequireUser}
  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, conn, attrs} <- A8FormDecode.params(conn, []), true <- method?(conn, attrs) do
      query = Plug.Conn.Query.decode(conn.query_string)
      attrs = Map.merge(Map.delete(attrs, "_method"), query)
      accept = get_req_header(conn, "accept") |> Enum.join(",")

      format =
        cond do
          attrs["format"] == "json" or String.contains?(accept, "application/json") -> :json
          String.contains?(accept, "text/vnd.turbo-stream.html") -> :turbo_stream
          true -> :unsupported
        end

      conn =
        conn
        |> assign(:api_tag, "stats_sharing")
        |> assign(:api_params, attrs)
        |> assign(:api_query, query)
        |> assign(:sharing_format, format)
        |> assign(
          :locale,
          Locale.resolve(nil, conn.assigns.current_user, conn.assigns.rails_session)
        )
        |> RequireUser.call([])

      if conn.halted, do: conn, else: RailsForm.call(conn, [])
    else
      _ ->
        conn
        |> assign(:api_tag, "stats_sharing")
        |> DawarichWeb.Api.Body.replay("sharing request envelope")
    end
  end

  defp method?(%{method: "PATCH"}, attrs), do: not Map.has_key?(attrs, "_method")

  defp method?(%{method: "POST"}, %{"_method" => method}) when is_binary(method),
    do: String.upcase(method) == "PATCH"

  defp method?(_, _), do: false
end
