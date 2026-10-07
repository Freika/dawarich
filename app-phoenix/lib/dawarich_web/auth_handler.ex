defmodule DawarichWeb.AuthHandler do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Accounts
  alias Dawarich.Auth.{ActionCsrf, Admission, Credentials}
  alias Dawarich.Auth.Otp.Start
  alias DawarichWeb.AuthOtp.Response
  alias DawarichWeb.{AuthMessages, AuthResponse, RailsAuth, RailsProxy, RequestURL}

  @routes Enum.map(~w(GET POST), &{&1, "/users/sign_in"}) ++
            Enum.map(~w(DELETE POST), &{&1, "/users/sign_out"})

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
           context(
             conn,
             opts,
             session,
             conn.req_headers,
             Admission.oidc?(),
             System.get_env("SELF_HOSTED") == "true"
           ),
         true <- owned?(conn, session, opts) do
      conn = put_private(conn, :auth_registration_enabled, registration)

      if Keyword.get(opts, :native, false) and conn.method == "POST" and Admission.oidc?() and
           System.get_env("ALLOW_EMAIL_PASSWORD_LOGIN", "true") != "true" do
        AuthResponse.denied(
          conn,
          "controllers.users.sessions.email_password_login_is_disabled_please_use_oidc_to_sign"
        )
      else
        dispatch(conn, opts)
      end
    else
      _ -> fallback(conn, opts)
    end
  end

  defp context(_conn, opts, session, headers, oidc, self_hosted) do
    if Keyword.get(opts, :native, false),
      do: :ok,
      else: Admission.context(session, headers, oidc, self_hosted)
  end

  defp owned?(%{request_path: "/users/sign_out"} = conn, session, opts) do
    user =
      if Keyword.get(opts, :native, false),
        do: conn.assigns.current_user,
        else: Accounts.from_session(session, DateTime.utc_now())

    match?(%Accounts.User{}, user)
  end

  defp owned?(conn, _session, _opts),
    do: conn.method == "GET" or is_nil(conn.assigns.current_user)

  def route?(conn), do: {conn.method, conn.request_path} in @routes

  defp dispatch(%{method: "GET", assigns: %{current_user: %Accounts.User{}}} = conn, _opts),
    do: AuthResponse.already_authenticated(conn)

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
                conn |> send_resp(400, "Invalid credential request") |> halt()
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

  defp read_all(%{private: %{dawarich_raw_body: raw}} = conn, []) do
    if byte_size(raw) <= 65_536, do: {:ok, raw, conn}, else: {:error, conn}
  end

  defp read_all(conn, acc) do
    remaining = 65_536 - IO.iodata_length(acc)

    case read_body(conn, length: max(remaining, 1), read_length: 65_536) do
      {:more, raw, conn} when byte_size(raw) < remaining ->
        read_all(conn, [acc, raw])

      {:ok, raw, conn} when byte_size(raw) <= remaining ->
        {:ok, IO.iodata_to_binary([acc, raw]), conn}

      {:more, _, conn} ->
        {:error, conn}

      {:ok, _, conn} ->
        {:error, conn}

      {:error, _} ->
        {:error, conn}
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
        DawarichWeb.NotificationSession.signed_out(conn.assigns.rails_session)
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
      |> Map.put_new(
        :self_hosted,
        System.get_env(
          "SELF_HOSTED",
          if(Keyword.get(opts, :native, false), do: "true", else: "false")
        ) == "true"
      )
      |> Map.put(:native, Keyword.get(opts, :native, false))
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
          {:challenge, _user, pending} ->
            Response.form(conn, pending, context)

          :ordinary ->
            credentials_login(conn, params, opts)

          {:handoff, reason} when reason in [:password, :locked] ->
            if Keyword.get(opts, :native, false),
              do: credentials_login(conn, params, opts),
              else: fallback(conn, opts)

          {:handoff, _} ->
            fallback(conn, opts)
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
    {:ok, ip} = Dawarich.Auth.CredentialsClosure.client_ip(conn)

    context = %{
      native: Keyword.get(opts, :native, false),
      ip: ip,
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
    case {Keyword.get(opts, :native, false), Keyword.get(opts, :fallback)} do
      {true, _} -> conn |> send_resp(422, "Invalid authentication request") |> halt()
      {_, fun} when is_function(fun, 1) -> fun.(conn)
      {_, nil} -> RailsProxy.call(conn, Application.fetch_env!(:dawarich, :rails_upstream))
    end
  end
end
