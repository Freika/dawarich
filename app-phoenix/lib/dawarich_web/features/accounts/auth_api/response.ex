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

  def result(conn, {:retry_after, retry, result}, context),
    do: result(put_resp_header(conn, "retry-after", to_string(retry)), result, context)

  def result(conn, {:success, status, payload}, _context), do: reply(conn, status, payload)
  def result(conn, {:challenge, token}, _context), do: challenge(conn, token)
  def result(conn, {:error, status, payload}, _context), do: reply(conn, status, object(payload))

  def result(conn, {:auth_error, status, key, bindings}, context) do
    message = DawarichWeb.Translate.t(Map.get(context, :locale, "en"), key, bindings)
    reply(conn, status, {:object, [{"error", "auth_failed"}, {"message", message}]})
  end

  def object(value) when is_map(value),
    do: {:object, Enum.map(value, fn {k, v} -> {k, object(v)} end)}

  def object(value) when is_list(value), do: Enum.map(value, &object/1)
  def object(value), do: value

  def success(conn, payload), do: reply(conn, 200, payload)
  def challenge(conn, token), do: reply(conn, 202, challenge_term(token))

  def challenge_term(token),
    do: {:object, [{"two_factor_required", true}, {"challenge_token", token}, {"ttl", 300}]}

  def reply(conn, status, term),
    do:
      conn
      |> put_resp_header("x-dawarich-auth-owner", "native-api-auth")
      |> Respond.json(status, term)
end
