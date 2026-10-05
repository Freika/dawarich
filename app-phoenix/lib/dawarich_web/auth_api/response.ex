defmodule DawarichWeb.AuthApi.Response do
  @moduledoc false
  import Plug.Conn
  alias DawarichWeb.Api.Respond
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def preflight(conn, term) do
    true = conn.assigns.api_tag == "api"
    true = is_integer(conn.assigns.api_started)
    true = is_list(conn.assigns.api_headers)
    true = is_binary(conn.assigns.api_request_id)
    true = is_boolean(conn.assigns.api_vary)
    Ruby.json(term) |> IO.iodata_to_binary()
    :ok
  end

  def success(conn, payload), do: reply(conn, 200, payload)
  def challenge(conn, token), do: reply(conn, 202, challenge_term(token))

  def challenge_term(token),
    do: {:object, [{"two_factor_required", true}, {"challenge_token", token}, {"ttl", 300}]}

  defp reply(conn, status, term),
    do:
      conn
      |> put_resp_header("x-dawarich-auth-owner", "native-api-auth")
      |> Respond.json(status, term)
end
