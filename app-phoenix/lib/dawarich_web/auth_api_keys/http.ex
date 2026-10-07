defmodule DawarichWeb.AuthApiKeys.Http do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.{Accounts, RailsCookies, RailsSecret}
  alias Dawarich.Auth.{AccountChanges, ActionCsrf, Admission, ApiKeys}
  alias DawarichWeb.{RailsAuth, RailsHeaders, RailsProxy, RequestURL}

  @path "/settings/generate_api_key"
  @turbo "text/vnd.turbo-stream.html, text/html, application/xhtml+xml"
  @browser "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"

  def init(opts), do: opts
  def route?(conn), do: conn.method == "POST" and conn.request_path == @path

  def call(conn, opts) do
    if Keyword.get(opts, :enabled, false) == true and route?(conn) and
         Admission.headers(conn.req_headers) == :ok and html?(conn) do
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
      |> Map.put(:native, Keyword.get(opts, :native, false))

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
         :ok <- admission(session, conn, context),
         [[id], salt] <- session["warden.user.user.key"],
         {:ok, _actor} <- account(context).actor(id, salt, context),
         %Accounts.User{} <- Accounts.get(id) do
      {:ok, RailsAuth.call(conn, secret: secret), id, salt, context}
    else
      _ -> {:handoff, :identity}
    end
  rescue
    _ -> {:handoff, :identity}
  end

  defp account(context),
    do: if(context[:native], do: Dawarich.Auth.AccountClosure, else: AccountChanges)

  defp admission(session, conn, context),
    do:
      if(context[:native],
        do: :ok,
        else: Admission.context(session, conn.req_headers, context.oidc, context.self_hosted)
      )

  defp parse(conn, id, salt, opts, context) do
    with "" <- conn.query_string,
         [length] <- get_req_header(conn, "content-length"),
         true <- length =~ ~r/\A\d+\z/ and String.to_integer(length) <= 65_536,
         [] <- get_req_header(conn, "transfer-encoding"),
         [type] <- get_req_header(conn, "content-type"),
         true <- hd(String.split(type, ";")) == "application/x-www-form-urlencoded",
         {:ok, location} <- location(conn) do
      case read_all(conn, []) do
        {:ok, raw, conn} ->
          conn = put_private(conn, :dawarich_raw_body, raw)

          with {:ok, params} <-
                 Admission.form(raw, conn.query_string, ["authenticity_token", "_method"]),
               true <- is_nil(params["_method"]) or String.upcase(params["_method"]) == "POST",
               true <- csrf?(conn, params),
               {:ok, _actor} <- ApiKeys.rotate(id, salt, context) do
            conn
            |> RailsHeaders.call([])
            |> put_resp_header("x-dawarich-auth-owner", "native-api-keys")
            |> put_resp_header("location", location)
            |> put_resp_content_type("text/html")
            |> send_resp(302, "")
            |> halt()
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

  defp location(conn), do: {:ok, DawarichWeb.RailsRedirect.back(conn)}

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

  defp html?(conn) do
    get_req_header(conn, "accept") in [[], ["text/html"], ["*/*"], [@turbo], [@browser]]
  end

  defp fallback(conn, opts) do
    conn =
      case {Keyword.get(opts, :native, false), Keyword.get(opts, :fallback)} do
        {true, _} -> send_resp(conn, 422, "Invalid API key request")
        {_, fun} when is_function(fun, 1) -> fun.(conn)
        _ -> RailsProxy.call(conn, Application.fetch_env!(:dawarich, :rails_upstream))
      end

    halt(conn)
  end
end
