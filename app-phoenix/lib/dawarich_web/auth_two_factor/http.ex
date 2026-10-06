defmodule DawarichWeb.AuthTwoFactor.Http do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.{Accounts, RailsCookies, RailsSecret}
  alias Dawarich.Auth.{ActionCsrf, Admission, SessionCookie}
  alias Dawarich.Auth.TwoFactor.{Closure, Management, Secret}
  alias DawarichWeb.{RailsAuth, RailsProxy, RequestURL}
  alias DawarichWeb.AuthTwoFactor.Response

  @path "/settings/two_factor"
  @verify @path <> "/verify"
  @common ~w(authenticity_token commit utf8)

  def init(opts), do: opts
  def route?(conn), do: conn.request_path in [@path, @verify]

  def call(conn, opts) do
    if Keyword.get(opts, :enabled, false) == true and route?(conn) and
         ordinary?(conn) and Admission.headers(conn.req_headers) == :ok do
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
      |> Map.put_new(
        :self_hosted,
        if(Keyword.get(opts, :native, false),
          do: System.get_env("SELF_HOSTED", "true") != "false",
          else: System.get_env("SELF_HOSTED") == "true"
        )
      )
      |> Map.put(:native, Keyword.get(opts, :native, false))
      |> Map.put_new_lazy(:oidc, &Admission.oidc?/0)

    case identity(conn, context) do
      {:ok, conn, id, salt, context} -> parse(conn, id, salt, opts, context)
      _ -> fallback(conn, opts)
    end
  end

  defp identity(conn, context) do
    secret = Map.get_lazy(context, :secret, &RailsSecret.fetch/0)
    conn = fetch_cookies(conn)

    with true <- is_binary(secret) and secret != "",
         cookie when is_binary(cookie) <- conn.cookies["_dawarich_session"],
         {:ok, session} when is_map(session) <-
           RailsCookies.decrypt(cookie, "_dawarich_session", secret, DateTime.utc_now()),
         true <-
           context.native or
             Admission.context(session, conn.req_headers, context.oidc, context.self_hosted) ==
               :ok,
         [[id], salt] <- session["warden.user.user.key"],
         {:ok, _actor} <- actor(id, salt, context),
         %Accounts.User{} <- Accounts.get(id) do
      SessionCookie.for_form(session, secret)
      {:ok, RailsAuth.call(conn, secret: secret), id, salt, Map.put(context, :secret, secret)}
    else
      _ -> {:handoff, :identity}
    end
  rescue
    _ -> {:handoff, :identity}
  end

  defp actor(id, salt, context) do
    if context.native, do: Closure.actor(id, salt, context), else: Secret.actor(id, salt, context)
  end

  defp parse(%{method: "GET", request_path: @path} = conn, id, salt, opts, context) do
    if get_req_header(conn, "transfer-encoding") == [] and
         get_req_header(conn, "content-length") in [[], ["0"]] do
      dispatch(conn, :show, %{}, id, salt, opts, context)
    else
      fallback(conn, opts)
    end
  end

  defp parse(conn, id, salt, opts, context) do
    with true <- conn.method in ["POST", "DELETE"],
         [length] <- get_req_header(conn, "content-length"),
         true <- length =~ ~r/\A\d+\z/ and String.to_integer(length) <= 65_536,
         [] <- get_req_header(conn, "transfer-encoding"),
         [type] <- get_req_header(conn, "content-type"),
         true <- hd(String.split(type, ";")) == "application/x-www-form-urlencoded" do
      case read_all(conn, []) do
        {:ok, raw, conn} ->
          conn = put_private(conn, :dawarich_raw_body, raw)

          with {:ok, params} <-
                 Admission.form(
                   raw,
                   conn.query_string,
                   @common ++ ~w(otp_attempt password _method)
                 ),
               {:ok, action, method, fields} <- action(conn, params),
               true <- Enum.all?(Map.keys(params), &(&1 in (@common ++ fields))),
               false <- String.contains?(params["password"] || "", <<0>>),
               false <- String.contains?(params["otp_attempt"] || "", <<0>>),
               true <- csrf?(conn, params, method) do
            dispatch(conn, action, params, id, salt, opts, context)
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

  defp action(%{method: "POST", request_path: @path}, %{"_method" => "delete"}),
    do: {:ok, :disable, "DELETE", ~w(_method password otp_attempt)}

  defp action(%{method: "POST", request_path: @path}, params),
    do: if(Map.has_key?(params, "_method"), do: :handoff, else: {:ok, :setup, "POST", []})

  defp action(%{method: "POST", request_path: @verify}, params),
    do:
      if(Map.has_key?(params, "_method"),
        do: :handoff,
        else: {:ok, :verify, "POST", ["otp_attempt"]}
      )

  defp action(%{method: "DELETE", request_path: @path}, params),
    do:
      if(Map.has_key?(params, "_method"),
        do: :handoff,
        else: {:ok, :disable, "DELETE", ~w(password otp_attempt)}
      )

  defp action(_, _), do: :handoff

  defp dispatch(conn, action, params, id, salt, opts, context) do
    result =
      if context.native do
        Closure.call(action, id, salt, params, context)
      else
        case action do
          :show ->
            Management.show(id, salt, context)

          :setup ->
            Management.setup(id, salt, context)

          :verify ->
            Management.verify(id, salt, params["otp_attempt"], context)

          :disable ->
            Management.disable(id, salt, params["password"], params["otp_attempt"], context)
        end
      end

    case result do
      {:unavailable, _} ->
        Response.redirect(
          conn,
          :two_factor_authentication_is_not_configured_on_this_instance,
          context
        )

      {status, %{kind: :redirect, reason: reason}} when status in [:ok, :error] ->
        Response.redirect(conn, reason, context)

      {:ok, render} ->
        Response.form(conn, render.user, render, 200, context)

      {:error, render} ->
        Response.form(conn, render.user, render, 422, context)

      {:handoff, _} ->
        fallback(conn, opts)
    end
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

  defp csrf?(conn, params, method) do
    tokens =
      Enum.reject(
        [params["authenticity_token"] | get_req_header(conn, "x-csrf-token")],
        &is_nil/1
      )

    get_req_header(conn, "origin") in [[], [RequestURL.base(conn)]] and length(tokens) == 1 and
      ActionCsrf.valid?(conn.assigns.rails_session, hd(tokens), method, conn.request_path)
  end

  defp ordinary?(conn) do
    conn.query_string == "" and get_req_header(conn, "x-requested-with") == [] and
      Enum.all?(get_req_header(conn, "accept"), fn value ->
        hd(String.split(value, [",", ";"])) in ["text/html", "*/*"] and
          not String.contains?(value, ["application/json", "text/vnd.turbo-stream.html"])
      end)
  end

  defp fallback(conn, opts) do
    conn =
      if Keyword.get(opts, :native, false) do
        send_resp(conn, 422, "Invalid two-factor request")
      else
        case Keyword.get(opts, :fallback) do
          fun when is_function(fun, 1) -> fun.(conn)
          _ -> RailsProxy.call(conn, Application.fetch_env!(:dawarich, :rails_upstream))
        end
      end

    halt(conn)
  end
end
