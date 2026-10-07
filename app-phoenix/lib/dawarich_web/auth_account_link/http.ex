defmodule DawarichWeb.AuthAccountLink.Http do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.{Jobs, RailsCookies, RailsSecret}
  alias Dawarich.Auth.{ActionCsrf, Admission, SessionCookie}
  alias Dawarich.Auth.AccountLink.{Pending, Confirmation, SignIn}
  alias DawarichWeb.{RailsAuth, RailsProxy, RateLimit, RequestURL}
  alias DawarichWeb.AuthAccountLink.Response
  @closed_fields ~w(token password authenticity_token commit utf8)
  @closed_paths ~w(/auth/account_link /auth/account_link/challenge /auth/account_link/email)
  @path "/auth/account_link/challenge"
  @fields ~w(authenticity_token password commit utf8)

  def init(opts), do: opts
  def route?(conn), do: conn.request_path == @path
  def closure_route?(conn), do: conn.request_path in @closed_paths

  def call(conn, opts) do
    if Keyword.get(opts, :closure, false),
      do: closed_call(conn, opts),
      else: legacy_call(conn, opts)
  end

  defp legacy_call(conn, opts) do
    if Keyword.get(opts, :enabled, false) == true and conn.request_path == @path and
         ordinary?(conn) and
         Admission.headers(conn.req_headers) == :ok do
      conn = conn |> DawarichWeb.HostAuthorization.call([]) |> DawarichWeb.ForceSSL.call([])
      if conn.halted, do: conn, else: admit(conn, opts)
    else
      fallback(conn, opts)
    end
  end

  defp admit(conn, opts) do
    context =
      Keyword.get(opts, :context, %{})
      |> Map.put_new(:self_hosted, System.get_env("SELF_HOSTED") == "true")
      |> Map.put_new_lazy(:ip, fn -> DawarichWeb.RailsRemoteIp.ip(conn) end)

    case identity(conn, context) do
      {:ok, conn, context} -> parse(conn, opts, context)
      _ -> fallback(conn, opts)
    end
  end

  defp identity(conn, context) do
    secret = Map.get_lazy(context, :secret, &RailsSecret.fetch/0)
    now = Map.get(context, :clock, &DateTime.utc_now/0).()
    cookies = get_req_header(conn, "cookie")
    conn = fetch_cookies(conn)

    with true <- is_binary(secret) and secret != "",
         true <-
           length(cookies) == 1 and
             length(Regex.scan(~r/(?:\A|;)\s*_dawarich_session=/, hd(cookies))) == 1,
         nil <- conn.cookies["remember_user_token"],
         cookie when is_binary(cookie) <- conn.cookies["_dawarich_session"],
         {:ok, session} when is_map(session) <-
           RailsCookies.decrypt(cookie, "_dawarich_session", secret, now),
         :ok <- Admission.context(session, conn.req_headers, false, context.self_hosted),
         {:ok, _pending} <- Pending.valid(session, DateTime.to_unix(now), context) do
      SessionCookie.for_form(session, secret)
      {:ok, RailsAuth.call(conn, secret: secret, now: now), Map.put(context, :secret, secret)}
    else
      _ -> {:handoff, :identity}
    end
  rescue
    _ -> {:handoff, :identity}
  end

  defp parse(%{method: "GET"} = conn, opts, context) do
    with [] <- get_req_header(conn, "transfer-encoding"),
         true <- get_req_header(conn, "content-length") in [[], ["0"]],
         true <- supported_flash?(conn.assigns.rails_session["flash"]),
         {:ok, pending} <- Pending.valid(conn.assigns.rails_session, now(context), context) do
      Response.form(conn, pending, context)
    else
      _ -> fallback(conn, opts)
    end
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
               true <- csrf?(conn, params),
               {:ok, prepared} <-
                 Confirmation.prepare(conn.assigns.rails_session, params["password"], context) do
            count(conn, prepared, opts, context)
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

  defp supported_flash?(nil), do: true

  defp supported_flash?(%{"flashes" => flashes}) when is_map(flashes),
    do: Enum.all?(Map.values(flashes), &is_binary/1)

  defp supported_flash?(_), do: false

  defp count(conn, prepared, opts, context) do
    at = Map.get(context, :rate_now, System.os_time(:second))
    repo = Map.get(context, :rate_repo, Jobs.repo())

    case RateLimit.decide(conn, %{now: at, repo: repo, self_hosted: true, plan: &RateLimit.plan/1}) do
      {:pass, conn, counted, _token} ->
        complete(put_private(conn, :dawarich_rate_limit, counted), prepared, context)

      {:throttled, conn, _counted, data} ->
        RateLimit.throttled(conn, data, at, nil)

      {:blocked, conn} ->
        RateLimit.blocked(conn)

      {:defer, conn, counted, reason} ->
        conn = put_private(conn, :dawarich_rate_limit, counted)

        if reason in [
             "counter store: DBConnection.ConnectionError",
             "counter store: Postgrex.Error"
           ] do
          case RateLimit.release(conn, repo) do
            {:error, conn} -> complete(conn, prepared, context)
            conn -> fallback(conn, opts)
          end
        else
          fallback(conn, opts)
        end
    end
  end

  defp complete(conn, prepared, context) do
    preview =
      Map.merge(prepared, %{
        kind: if(prepared.user.otp_required_for_login, do: :link_only, else: :sign_in),
        session: Map.drop(prepared.session, ~w(pending_oauth_link pending_oauth_link_attempts))
      })

    :ok = Response.preflight(conn, preview, context)
    {:ok, linked} = Confirmation.commit(prepared, context)
    {:ok, result} = SignIn.commit(linked, context)
    Response.completed(conn, result, context)
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

  defp now(context), do: Map.get(context, :clock, &DateTime.utc_now/0).() |> DateTime.to_unix()

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

  defp fallback(conn, opts) do
    conn =
      case Keyword.get(opts, :fallback) do
        fun when is_function(fun, 1) -> fun.(conn)
        _ -> RailsProxy.call(conn, Application.fetch_env!(:dawarich, :rails_upstream))
      end

    halt(conn)
  end

  defp closed_call(conn, opts) do
    if Keyword.get(opts, :enabled, false) and conn.request_path in @closed_paths do
      conn = conn |> DawarichWeb.HostAuthorization.call([]) |> DawarichWeb.ForceSSL.call([])
      conn = if conn.halted, do: conn, else: DawarichWeb.RateLimit.call(conn, [])
      if conn.halted, do: conn, else: closed_dispatch(conn, opts)
    else
      case opts[:fallback] do
        fun when is_function(fun, 1) -> fun.(conn)
        _ -> conn
      end
    end
  end

  defp closed_dispatch(conn, opts) do
    context =
      Keyword.get(opts, :context, %{})
      |> Map.put_new(:ip, DawarichWeb.RailsRemoteIp.ip(conn))
      |> Map.put_new(:base_url, RequestURL.base(conn))

    conn = RailsAuth.call(conn, [])

    context =
      Map.put(context, :locale, DawarichWeb.Locale.resolve(nil, nil, conn.assigns.rails_session))

    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("pragma", "no-cache")

    with :ok <- Admission.headers(conn.req_headers),
         {:ok, params, conn} <- closed_parameters(conn),
         true <- conn.method == "GET" or closed_csrf?(conn, params) do
      Dawarich.Auth.AccountLink.Closure.route(conn, params, context)
    else
      false -> conn |> send_resp(422, "Invalid authenticity token") |> halt()
      _ -> conn |> send_resp(400, "Invalid account link request") |> halt()
    end
  rescue
    _ -> Dawarich.Auth.Providers.Failure.terminal(conn)
  end

  defp closed_parameters(%{method: "POST"} = conn) do
    with [type] <- get_req_header(conn, "content-type"),
         true <- hd(String.split(type, ";")) == "application/x-www-form-urlencoded",
         {:ok, body, conn} <- closed_body(conn),
         {:ok, params} <- Admission.form(body, conn.query_string, @closed_fields),
         do: {:ok, params, conn}
  end

  defp closed_parameters(conn) do
    with {:ok, params} <- Admission.form(conn.query_string, "", @closed_fields),
         do: {:ok, params, conn}
  end

  defp closed_csrf?(conn, params) do
    get_req_header(conn, "origin") in [[], [RequestURL.base(conn)]] and
      Enum.any?(
        [params["authenticity_token"] | get_req_header(conn, "x-csrf-token")],
        &ActionCsrf.valid?(conn.assigns.rails_session, &1, "POST", conn.request_path)
      )
  end

  defp closed_body(%{private: %{dawarich_raw_body: raw}} = conn), do: {:ok, raw, conn}
  defp closed_body(conn), do: read_body(conn, length: 65536)
end
