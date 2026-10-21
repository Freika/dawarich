defmodule DawarichWeb.UnlockAdmission do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias DawarichWeb.Api.Body

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case admission(conn) do
      :ok -> conn
      {:replay, reason} -> Body.replay(conn, reason)
    end
  end

  defp admission(conn) do
    params = conn.assigns.api_params

    cond do
      Body.kind(conn) not in [:none, :form] ->
        {:replay, "unlock body type"}

      get_req_header(conn, "x-http-method-override") != [] ->
        {:replay, "method override"}

      Map.has_key?(params, "_method") ->
        {:replay, "method override"}

      Map.has_key?(params, "client") ->
        {:replay, "session-writing parameter"}

      Enum.any?(
        ~w(locale format),
        &(Map.has_key?(params, &1) and not Map.has_key?(conn.assigns.api_query, &1))
      ) ->
        {:replay, "body locale or format"}

      not (is_binary(params["phrase"]) or is_nil(params["phrase"])) ->
        {:replay, "phrase shape"}

      true ->
        :ok
    end
  end
end
