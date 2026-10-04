defmodule DawarichWeb.AuthAccount.Http do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.{Accounts, RailsCookies, RailsSecret}
  alias Dawarich.Auth.{AccountChanges, ActionCsrf, Admission}
  alias DawarichWeb.{RailsAuth, RailsProxy, RequestURL}
  alias DawarichWeb.AuthAccount.Response

  @fields ~w(user[email] user[password] user[password_confirmation] user[current_password] authenticity_token commit utf8 _method)
  @routes [{"PUT", "/users"}, {"PATCH", "/users"}, {"POST", "/users"}]

  def init(opts), do: opts
  def route?(conn), do: {conn.method, conn.request_path} in @routes

  def call(conn, opts) do
    if Keyword.get(opts, :enabled, false) == true and route?(conn) and
         Admission.headers(conn.req_headers) == :ok and html?(conn) do
      conn = conn |> DawarichWeb.HostAuthorization.call([]) |> DawarichWeb.ForceSSL.call([])
      if conn.halted, do: conn, else: admit(conn, opts)
    else
      fallback(conn, opts)
    end
  end

  defp admit(conn, opts) do
    context = Keyword.get(opts, :context, %{})

    context =
      context
      |> Map.put_new(:self_hosted, System.get_env("SELF_HOSTED") == "true")
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
         :ok <- Admission.context(session, conn.req_headers, context.oidc, context.self_hosted),
         [[id], salt] <- session["warden.user.user.key"],
         {:ok, _actor} <- AccountChanges.actor(id, salt, context),
         %Accounts.User{} <- Accounts.get(id) do
      conn = RailsAuth.call(conn, secret: secret)
      locale = DawarichWeb.Locale.resolve(nil, conn.assigns.current_user, session)
      {:ok, conn, id, salt, context |> Map.put(:secret, secret) |> Map.put(:locale, locale)}
    else
      _ -> {:handoff, :identity}
    end
  rescue
    _ -> {:handoff, :identity}
  end

  defp parse(conn, id, salt, opts, context) do
    with "" <- conn.query_string,
         [length] <- get_req_header(conn, "content-length"),
         true <- length =~ ~r/\A\d+\z/ and String.to_integer(length) <= 65_536,
         [] <- get_req_header(conn, "transfer-encoding"),
         [type] <- get_req_header(conn, "content-type"),
         true <- hd(String.split(type, ";")) == "application/x-www-form-urlencoded" do
      case read_all(conn, []) do
        {:ok, raw, conn} ->
          conn = put_private(conn, :dawarich_raw_body, raw)

          with {:ok, params} <- Admission.form(raw, conn.query_string, @fields),
               {:ok, method} <- method(conn, params),
               true <- csrf?(conn, params, method) do
            user_params =
              Map.new(
                for {"user[" <> key, value} <- params, do: {String.trim_trailing(key, "]"), value}
              )

            case AccountChanges.update(id, salt, user_params, context) do
              {:ok, actor} -> Response.updated(conn, actor, context)
              {:error, render} -> Response.form(conn, conn.assigns.current_user, render, context)
              {:handoff, _} -> fallback(conn, opts)
            end
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

  defp read_all(conn, acc) do
    case read_body(conn, RailsProxy.read_options()) do
      {:more, raw, conn} -> read_all(conn, [acc, raw])
      {:ok, raw, conn} -> {:ok, IO.iodata_to_binary([acc, raw]), conn}
      {:error, _} -> {:error, conn}
    end
  end

  defp method(%{method: "POST"}, %{"_method" => "put"}), do: {:ok, "PUT"}
  defp method(%{method: "POST"}, %{"_method" => "patch"}), do: {:ok, "PATCH"}

  defp method(%{method: method}, params) when method in ["PUT", "PATCH"],
    do: if(Map.has_key?(params, "_method"), do: {:handoff, :method}, else: {:ok, method})

  defp method(_, _), do: {:handoff, :method}

  defp csrf?(conn, params, method) do
    tokens =
      Enum.reject(
        [params["authenticity_token"] | get_req_header(conn, "x-csrf-token")],
        &is_nil/1
      )

    origin = get_req_header(conn, "origin")

    origin in [[], [RequestURL.base(conn)]] and length(tokens) == 1 and
      ActionCsrf.valid?(conn.assigns.rails_session, hd(tokens), method, "/users")
  end

  defp html?(conn) do
    Enum.all?(get_req_header(conn, "accept"), fn value ->
      hd(String.split(value, [",", ";"])) in ["text/html", "*/*"] and
        not String.contains?(value, ["application/json", "text/vnd.turbo-stream.html"])
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
end
