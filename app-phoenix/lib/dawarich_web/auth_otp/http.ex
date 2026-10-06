defmodule DawarichWeb.AuthOtp.Http do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.{RailsCookies, RailsSecret}
  alias Dawarich.Auth.{ActionCsrf, Admission, SessionCookie}
  alias Dawarich.Auth.Otp.Completion
  alias DawarichWeb.{RailsAuth, RailsProxy, RequestURL}
  alias DawarichWeb.AuthOtp.Response
  @path "/users/otp_challenge"
  @fields ~w(authenticity_token otp_attempt commit utf8)

  def init(opts), do: opts
  def route?(conn), do: conn.request_path == @path

  def call(conn, opts) do
    if Keyword.get(opts, :enabled, false) == true and route?(conn) and ordinary?(conn) and
         Admission.headers(conn.req_headers) == :ok do
      conn = conn |> DawarichWeb.HostAuthorization.call([]) |> DawarichWeb.ForceSSL.call([])
      conn = if conn.halted, do: conn, else: DawarichWeb.RateLimit.call(conn, [])
      if conn.halted, do: conn, else: admit(conn, opts)
    else
      fallback(conn, opts)
    end
  end

  defp admit(conn, opts) do
    context =
      Keyword.get(opts, :context, %{})
      |> Map.put_new(:self_hosted, System.get_env("SELF_HOSTED") == "true")
      |> Map.put_new_lazy(:oidc, &Admission.oidc?/0)
      |> Map.put_new_lazy(:ip, fn -> conn.remote_ip |> :inet.ntoa() |> to_string() end)

    case identity(conn, context) do
      {:ok, conn, context} -> parse(conn, opts, context)
      _ -> fallback(conn, opts)
    end
  end

  defp identity(conn, context) do
    secret = Map.get_lazy(context, :secret, &RailsSecret.fetch/0)
    now = Map.get(context, :clock, &DateTime.utc_now/0).()
    conn = fetch_cookies(conn)

    with true <- is_binary(secret) and secret != "",
         cookie when is_binary(cookie) <- conn.cookies["_dawarich_session"],
         {:ok, session} when is_map(session) <-
           RailsCookies.decrypt(cookie, "_dawarich_session", secret, now),
         :ok <- Admission.context(session, conn.req_headers, context.oidc, context.self_hosted),
         nil <- session["warden.user.user.key"],
         true <- local_return?(session["user_return_to"]) do
      conn = RailsAuth.call(conn, secret: secret, now: now)

      if is_nil(conn.assigns.current_user) and is_nil(conn.assigns.rails_locked) do
        SessionCookie.for_form(session, secret)
        {:ok, conn, Map.put(context, :secret, secret)}
      else
        {:handoff, :identity}
      end
    else
      _ -> {:handoff, :identity}
    end
  rescue
    _ -> {:handoff, :identity}
  end

  defp parse(conn, opts, context) do
    with true <- conn.method == "POST",
         [length] <- get_req_header(conn, "content-length"),
         true <- length =~ ~r/\A\d+\z/ and String.to_integer(length) <= 65_536,
         [] <- get_req_header(conn, "transfer-encoding"),
         [type] <- get_req_header(conn, "content-type"),
         true <- hd(String.split(type, ";")) == "application/x-www-form-urlencoded" do
      case read_all(conn, []) do
        {:ok, raw, conn} ->
          conn = put_private(conn, :dawarich_raw_body, raw)

          with {:ok, params} <- Admission.form(raw, conn.query_string, @fields),
               true <- csrf?(conn, params) do
            dispatch(conn, params["otp_attempt"], opts, context)
          else
            _ -> fallback(conn, opts)
          end

        {:error, conn} ->
          conn |> send_resp(400, "") |> halt()
      end
    else
      _ -> fallback(conn, opts)
    end
  end

  defp dispatch(conn, code, opts, context) do
    case Completion.prepare(conn.assigns.rails_session, code, context) do
      {:ok, prepared} ->
        {:ok, result} = Completion.commit(prepared, context)
        Response.signed_in(conn, result, context)

      {:expired, cleared} ->
        Response.expired(conn, cleared, context)

      {:handoff, :invalid_code} ->
        if Keyword.get(opts, :native, false) do
          native_failure(conn, context)
        else
          fallback(conn, opts)
        end

      {:handoff, _} ->
        fallback(conn, opts)
    end
  end

  defp native_failure(conn, context) do
    case Dawarich.Auth.Otp.Failure.record(conn.assigns.rails_session, context) do
      {:form, session, reason} ->
        conn =
          conn
          |> assign(:rails_session, session)
          |> fetch_query_params()
          |> DawarichWeb.Locale.call([])
          |> DawarichWeb.LayoutAssigns.call([])

        {session, _} = encoded = SessionCookie.for_form(session, context.secret)
        token = DawarichWeb.RailsCsrf.masked_form_token(session, @path, "POST")

        alert =
          DawarichWeb.Translate.t(
            conn.assigns.locale,
            "controllers.users.otp_challenge.#{reason}",
            %{}
          )

        assigns =
          Map.merge(conn.assigns, %{
            __changed__: nil,
            flash: %{"alert" => alert},
            page_title: nil,
            rails_csrf_token: token
          })

        content = DawarichWeb.AuthOtp.Form.page(assigns)
        app = DawarichWeb.Layouts.app(Map.put(assigns, :inner_content, content))

        body =
          DawarichWeb.Layouts.root(Map.put(assigns, :inner_content, app))
          |> Phoenix.HTML.Safe.to_iodata()

        conn
        |> DawarichWeb.AuthCookie.session(encoded)
        |> DawarichWeb.RailsHeaders.call([])
        |> put_resp_header("x-dawarich-auth-owner", "native-otp")
        |> put_resp_content_type("text/html")
        |> send_resp(422, body)
        |> halt()

      {:redirect, session, reason} ->
        locale = DawarichWeb.Locale.resolve(nil, nil, session)
        alert = DawarichWeb.Translate.t(locale, "controllers.users.otp_challenge.#{reason}", %{})
        session = Map.put(session, "flash", %{"discard" => [], "flashes" => %{"alert" => alert}})

        conn
        |> DawarichWeb.AuthCookie.session(SessionCookie.for_form(session, context.secret))
        |> DawarichWeb.RailsHeaders.call([])
        |> put_resp_header("location", RequestURL.base(conn) <> "/users/sign_in")
        |> send_resp(302, "")
        |> halt()

      {:error, _} ->
        conn |> send_resp(500, "OTP notification unavailable") |> halt()
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

  defp csrf?(conn, params) do
    tokens =
      Enum.reject(
        [params["authenticity_token"] | get_req_header(conn, "x-csrf-token")],
        &is_nil/1
      )

    get_req_header(conn, "origin") in [[], [RequestURL.base(conn)]] and length(tokens) == 1 and
      ActionCsrf.valid?(conn.assigns.rails_session, hd(tokens), "POST", @path)
  end

  defp ordinary?(conn) do
    conn.query_string == "" and get_req_header(conn, "x-requested-with") == [] and
      Enum.all?(get_req_header(conn, "accept"), fn value ->
        String.trim(hd(String.split(value, [",", ";"]))) in [
          "text/html",
          "application/xhtml+xml",
          "*/*"
        ] and
          not String.contains?(value, ["application/json", "text/vnd.turbo-stream.html"]) and
          not Regex.match?(~r/;\s*q=0(?:\.0*)?(?:\s*[,;]|\s*$)/, value)
      end)
  end

  defp local_return?(nil), do: true

  defp local_return?("/" <> rest = path),
    do:
      not String.starts_with?(rest, "/") and
        not String.contains?(path, ["\\", <<0>>, <<9>>, <<10>>, <<13>>])

  defp local_return?(_), do: false

  defp fallback(conn, opts) do
    conn =
      case {Keyword.get(opts, :native, false), Keyword.get(opts, :fallback)} do
        {true, _} -> send_resp(conn, 422, "Invalid OTP request")
        {_, fun} when is_function(fun, 1) -> fun.(conn)
        _ -> RailsProxy.call(conn, Application.fetch_env!(:dawarich, :rails_upstream))
      end

    halt(conn)
  end
end
