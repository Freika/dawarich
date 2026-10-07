defmodule DawarichWeb.RailsForm do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias Dawarich.Accounts
  alias DawarichWeb.{RailsCsrf, RequestURL}
  alias DawarichWeb.Api.Body

  @session_writers ~w(locale client aff via)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case admission(conn) do
      :ok -> conn
      {:replay, reason} -> Body.replay(conn, reason)
    end
  end

  @doc false
  def admission(conn, opts \\ []) do
    with :ok <- content_type(conn),
         :ok <- headers(conn),
         :ok <- method(conn, opts),
         :ok <- session_writers(conn),
         :ok <- signed_in(conn, opts),
         :ok <- origin(get_req_header(conn, "origin"), conn),
         do: token(conn)
  end

  defp content_type(conn),
    do: if(Body.kind(conn) == :json, do: {:replay, "content type"}, else: :ok)

  defp headers(conn) do
    if Enum.any?(conn.req_headers, fn {name, _value} -> String.contains?(name, "_") end) or
         Enum.any?(~w(cookie x-csrf-token), &(length(get_req_header(conn, &1)) > 1)),
       do: {:replay, "ambiguous headers"},
       else: :ok
  end

  defp method(conn, opts) do
    override = conn.assigns.api_params["_method"]

    cond do
      get_req_header(conn, "x-http-method-override") != [] ->
        {:replay, "method override"}

      Map.has_key?(conn.assigns.api_query, "_method") ->
        {:replay, "method override"}

      is_nil(override) ->
        :ok

      is_binary(override) and String.upcase(override) == "POST" ->
        :ok

      is_binary(override) and String.upcase(override) in Keyword.get(opts, :allowed_overrides, []) ->
        :ok

      true ->
        {:replay, "method override"}
    end
  end

  defp session_writers(conn) do
    if get_req_header(conn, "x-dawarich-client") != [] or
         Enum.any?(@session_writers, &Map.has_key?(conn.assigns.api_params, &1)),
       do: {:replay, "session-writing parameter"},
       else: :ok
  end

  defp signed_in(%{assigns: %{current_user: nil}}, opts) do
    if Keyword.get(opts, :anonymous, false), do: :ok, else: {:replay, "not signed in by session"}
  end

  defp signed_in(conn, _opts) do
    with %Accounts.User{id: id} <- conn.assigns.current_user,
         %Accounts.User{id: ^id} <-
           Accounts.from_session(conn.assigns.rails_session, DateTime.utc_now()) do
      :ok
    else
      _ -> {:replay, "not signed in by session"}
    end
  rescue
    error -> {:replay, "session lookup failed: " <> inspect(error.__struct__)}
  end

  defp origin([], _conn), do: :ok

  defp origin([origin], conn),
    do: if(origin == RequestURL.base(conn), do: :ok, else: {:replay, "origin"})

  defp origin(_origins, _conn), do: {:replay, "origin"}

  defp token(conn) do
    session = conn.assigns.rails_session

    tokens = [
      conn.assigns.api_params["authenticity_token"] | get_req_header(conn, "x-csrf-token")
    ]

    if Enum.any?(tokens, &(is_binary(&1) and token_valid?(conn, session, &1))),
      do: :ok,
      else: {:replay, "authenticity token"}
  end

  def native_recalculation?(conn),
    do:
      Dawarich.Standalone.enabled?() and conn.method == "POST" and
        conn.path_info == ["tracks", "recalculation"]

  defp token_valid?(conn, session, token) do
    if native_recalculation?(conn),
      do:
        RailsCsrf.valid?(
          session,
          token,
          conn.request_path,
          conn.assigns[:map_write_method] || conn.method
        ),
      else: RailsCsrf.valid?(session, token)
  end
end
