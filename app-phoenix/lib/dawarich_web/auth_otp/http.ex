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

      {:handoff, _} ->
        fallback(conn, opts)
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
      case Keyword.get(opts, :fallback) do
        fun when is_function(fun, 1) -> fun.(conn)
        _ -> RailsProxy.call(conn, Application.fetch_env!(:dawarich, :rails_upstream))
      end

    halt(conn)
  end
end
