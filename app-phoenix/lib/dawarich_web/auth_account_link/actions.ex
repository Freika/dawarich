defmodule DawarichWeb.AuthAccountLink.Actions do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.Auth.{ActionCsrf, Admission}
  alias Dawarich.Auth.AccountLink.Closure
  alias Dawarich.Auth.Providers.{Accounts, Failure}
  alias DawarichWeb.{RailsAuth, RequestURL}
  alias DawarichWeb.AuthAccountLink.Response
  @closed_fields ~w(token password authenticity_token commit utf8)
  @closed_paths ~w(/auth/account_link /auth/account_link/challenge /auth/account_link/email)
  def route?(conn), do: conn.request_path in @closed_paths

  def call(conn, opts) do
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
      route(conn, params, context)
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

  def route(%{method: "GET", request_path: "/auth/account_link"} = conn, params, context) do
    case Closure.confirm(params["token"], conn.assigns.rails_session, context) do
      {:ok, result} -> completed(conn, result, context)
      {:error, reason} -> error(conn, reason, context)
    end
  end

  def route(%{method: "GET", request_path: "/auth/account_link/challenge"} = conn, _, context) do
    case Closure.pending(conn.assigns.rails_session, context) do
      {:ok, prepared} -> Response.form(conn, labeled(prepared, context), context)
      {:error, reason} -> error(conn, reason, context)
    end
  end

  def route(
        %{method: "POST", request_path: "/auth/account_link/challenge"} = conn,
        params,
        context
      ) do
    case Closure.password(conn.assigns.rails_session, params["password"], context) do
      {:ok, result} ->
        completed(conn, result, context)

      {:error, :incorrect_password, session} ->
        {:ok, prepared} = Closure.pending(session, context)
        conn = assign(conn, :rails_session, flash(session, "incorrect_password", %{}, context))

        conn = register_before_send(conn, &%{&1 | status: 422})

        Response.form(
          conn,
          labeled(%{prepared | session: conn.assigns.rails_session}, context),
          context
        )

      {:error, reason, session} ->
        error(assign(conn, :rails_session, session), reason, context)

      {:error, reason} ->
        error(conn, reason, context)
    end
  end

  def route(%{method: "POST", request_path: "/auth/account_link/email"} = conn, _, context) do
    with {:ok, prepared} <- Closure.pending(conn.assigns.rails_session, context) do
      label =
        prepared.pending["provider_label"] ||
          Accounts.label(prepared.pending["provider"], context)

      case Accounts.send_link(
             prepared.user,
             prepared.pending["provider"],
             prepared.pending["uid"],
             label,
             context
           ) do
        {:ok, :sent} ->
          Failure.redirect(
            conn,
            "/users/sign_in",
            "controllers.auth.account_links.confirmation_link_sent",
            %{"email" => prepared.user.email},
            context,
            "notice"
          )

        {:error, {:rate_limited, _}} ->
          error(conn, :rate_limited, context)

        {:error, _} ->
          Failure.terminal(conn)
      end
    else
      {:error, reason} -> error(conn, reason, context)
    end
  end

  def route(conn, _, _), do: conn |> send_resp(404, "") |> halt()

  defp completed(conn, result, context) do
    result = labeled(result, context)
    Response.completed(conn, result, context)
  end

  defp labeled(result, context) do
    pending =
      Map.put_new(
        result.pending,
        "provider_label",
        Accounts.label(result.pending["provider"], context)
      )

    %{result | pending: pending}
  end

  defp error(conn, reason, context), do: Failure.link_error(conn, reason, context)

  defp flash(session, key, bindings, context) do
    text =
      DawarichWeb.Translate.t(context.locale, "controllers.auth.account_links." <> key, bindings)

    Map.put(session, "flash", %{"discard" => [], "flashes" => %{"alert" => text}})
  end
end
