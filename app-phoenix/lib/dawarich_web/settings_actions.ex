defmodule DawarichWeb.SettingsActions do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.Accounts
  alias DawarichWeb.RailsForm

  def enabled?(_conn, _params), do: Dawarich.Standalone.enabled?()

  def admit(conn, methods, opts \\ []) do
    params = conn.assigns.api_params
    override = params["_method"]

    method =
      if conn.method == "POST" and is_binary(override),
        do: String.upcase(override),
        else: conn.method

    check =
      if opts[:locale], do: assign(conn, :api_params, Map.delete(params, "locale")), else: conn

    cond do
      is_nil(conn.assigns.current_user) ->
        {:error, 302}

      method not in methods ->
        {:error, 404}

      conn.assigns.api_query != %{} ->
        {:error, 422}

      method == "GET" ->
        if match?(
             %Accounts.User{},
             Accounts.from_session(conn.assigns.rails_session, DateTime.utc_now())
           ),
           do: :ok,
           else: {:error, 302}

      RailsForm.admission(check,
        allowed_overrides: methods,
        per_form: opts[:per_form],
        csrf_method: method
      ) != :ok ->
        {:error, 422}

      true ->
        :ok
    end
  end

  def reject(conn, 302),
    do: conn |> put_resp_header("location", "/users/sign_in") |> send_resp(302, "") |> halt()

  def reject(conn, status), do: conn |> send_resp(status, "") |> halt()
end
