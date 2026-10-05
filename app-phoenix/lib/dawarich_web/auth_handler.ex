defmodule DawarichWeb.AuthHandler do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Accounts
  alias Dawarich.Auth.{ActionCsrf, Admission, Credentials}
  alias Dawarich.Auth.Otp.Start
  alias DawarichWeb.AuthOtp.Response
  alias DawarichWeb.{AuthMessages, AuthResponse, RailsAuth, RailsProxy, RequestURL}

  @routes [
    {"GET", "/users/sign_in"},
    {"POST", "/users/sign_in"},
    {"DELETE", "/users/sign_out"},
    {"POST", "/users/sign_out"}
  ]

  def init(opts), do: opts

  def call(conn, opts) do
    if Keyword.get(opts, :enabled, false) and route?(conn) do
      if Admission.headers(conn.req_headers) == :ok do
        conn = conn |> DawarichWeb.HostAuthorization.call([]) |> DawarichWeb.ForceSSL.call([])
        conn = if conn.halted, do: conn, else: DawarichWeb.RateLimit.call(conn, [])
        if conn.halted, do: conn, else: admitted(conn, opts)
      else
        fallback(conn, opts)
      end
    else
      fallback(conn, opts)
    end
  end

  defp admitted(conn, opts) do
    conn = RailsAuth.call(conn, [])
    session = conn.assigns.rails_session

    with {:ok, registration} when is_boolean(registration) <-
           Keyword.fetch(opts, :registration_enabled),
         nil <- conn.assigns.rails_locked,
         false <-
           Enum.any?(get_req_header(conn, "accept"), &String.contains?(&1, "application/json")),
         :ok <-
           Admission.context(
             session,
             conn.req_headers,
             Admission.oidc?(),
             System.get_env("SELF_HOSTED") == "true"
           ),
         true <- owned?(conn, session) do
      dispatch(put_private(conn, :auth_registration_enabled, registration), opts)
    else
      _ -> fallback(conn, opts)
    end
  end

  defp owned?(%{request_path: "/users/sign_out"}, session),
    do: match?(%Accounts.User{}, Accounts.from_session(session, DateTime.utc_now()))

  defp owned?(conn, _session), do: is_nil(conn.assigns.current_user)

  def route?(conn), do: {conn.method, conn.request_path} in @routes

  defp dispatch(%{method: "GET", query_string: ""} = conn, _opts),
    do: AuthResponse.form(conn, "", nil, 200)

  defp dispatch(%{method: "GET"} = conn, opts), do: fallback(conn, opts)

  defp dispatch(conn, opts) do
    if not bounded_body?(conn) do
      fallback(conn, opts)
    else
      case get_req_header(conn, "content-type") do
        [type] ->
          if hd(String.split(type, ";")) == "application/x-www-form-urlencoded" do
            case read_all(conn, []) do
              {:ok, raw, conn} ->
                conn = put_private(conn, :dawarich_raw_body, raw)

                case Admission.form(raw, conn.query_string) do
                  {:ok, params} -> action(conn, params, opts)
                  _ -> fallback(conn, opts)
                end

              {:error, conn} ->
                halt(conn)
            end
          else
            fallback(conn, opts)
          end

        _ ->
          fallback(conn, opts)
      end
    end
  end

  defp bounded_body?(conn) do
    case get_req_header(conn, "content-length") do
      [length] ->
        length =~ ~r/\A\d+\z/ and String.to_integer(length) <= 65_536 and
          get_req_header(conn, "transfer-encoding") == []

      _ ->
        false
    end
  end

  defp read_all(%{private: %{dawarich_raw_body: raw}} = conn, []), do: {:ok, raw, conn}

  defp read_all(conn, acc) do
    case read_body(conn, RailsProxy.read_options()) do
      {:more, raw, conn} -> read_all(conn, [acc, raw])
      {:ok, raw, conn} -> {:ok, IO.iodata_to_binary([acc, raw]), conn}
      {:error, _} -> {:error, conn}
    end
  end

  defp action(conn, params, opts) do
    method = if conn.request_path == "/users/sign_out", do: "DELETE", else: "POST"
    tokens = [params["authenticity_token"] | get_req_header(conn, "x-csrf-token")]

    cond do
      method == "POST" and params["_method"] ->
        fallback(conn, opts)

      method == "DELETE" and conn.method == "POST" and params["_method"] != "delete" ->
        fallback(conn, opts)

      length(get_req_header(conn, "x-csrf-token")) > 1 or not origin?(conn) ->
        fallback(conn, opts)

      not Enum.any?(
        tokens,
        &ActionCsrf.valid?(conn.assigns.rails_session, &1, method, conn.request_path)
      ) ->
        fallback(conn, opts)

      method == "DELETE" ->
        Credentials.logout(conn.assigns.current_user.id)
        AuthResponse.signed_out(conn)

      true ->
        login(conn, params, opts)
    end
  end

  defp login(conn, params, opts) do
    if Keyword.get(opts, :otp_enabled, false),
      do: otp_login(conn, params, opts),
      else: credentials_login(conn, params, opts)
  end

  defp otp_login(conn, params, opts) do
    context =
      Keyword.get(opts, :otp_context, %{})
      |> Map.put_new(:self_hosted, System.get_env("SELF_HOSTED") == "true")
      |> Map.put_new_lazy(:oidc, &Admission.oidc?/0)
      |> Map.put(:remember, params["user[remember_me]"])

    cond do
      not Start.candidate?(params["user[email]"], context) ->
        credentials_login(conn, params, opts)

      not otp_document?(conn) or not local_return?(conn.assigns.rails_session["user_return_to"]) ->
        fallback(conn, opts)

      true ->
        case Start.prepare(
               params["user[email]"],
               params["user[password]"],
               conn.assigns.rails_session,
               context
             ) do
          {:challenge, _user, pending} -> Response.form(conn, pending, context)
          :ordinary -> credentials_login(conn, params, opts)
          {:handoff, _} -> fallback(conn, opts)
        end
    end
  end

  defp otp_document?(conn) do
    conn.query_string == "" and get_req_header(conn, "x-requested-with") == [] and
      Enum.all?(get_req_header(conn, "accept"), fn value ->
        String.trim(hd(String.split(value, [",", ";"]))) in [
          "text/html",
          "application/xhtml+xml",
          "*/*"
        ] and
          not String.contains?(value, ["application/json", "text/vnd.turbo-stream.html"]) and
          not Regex.match?(~r/;\s*q=0(?:\.0*)?(?:;|\z)/, value)
      end)
  end

  defp local_return?(nil), do: true

  defp local_return?("/" <> rest = path),
    do:
      not String.starts_with?(rest, "/") and
        not String.contains?(path, ["\\", "\t", "\r", "\n", <<0>>])

  defp local_return?(_), do: false

  defp credentials_login(conn, params, opts) do
    context = %{
      ip: to_string(:inet.ntoa(conn.remote_ip)),
      remember: params["user[remember_me]"] == "1"
    }

    case Credentials.login(params["user[email]"], params["user[password]"], context) do
      {:ok, %{user: user, remember: remember}} ->
        AuthResponse.signed_in(conn, user, remember)

      {:error, :invalid} ->
        AuthResponse.form(conn, params["user[email]"], AuthMessages.invalid(conn), 422)

      {:handoff, _} ->
        fallback(conn, opts)
    end
  end

  defp origin?(conn) do
    case get_req_header(conn, "origin") do
      [] -> true
      [origin] -> origin == RequestURL.base(conn)
      _ -> false
    end
  end

  defp fallback(conn, opts) do
    case Keyword.get(opts, :fallback) do
      fun when is_function(fun, 1) -> fun.(conn)
      nil -> RailsProxy.call(conn, Application.fetch_env!(:dawarich, :rails_upstream))
    end
  end
end
