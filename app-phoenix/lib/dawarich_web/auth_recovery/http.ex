defmodule DawarichWeb.AuthRecovery.Http do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Auth.{ActionCsrf, Admission, SessionCookie}
  alias Dawarich.Auth.Recovery.Flow
  alias DawarichWeb.{AuthCookie, RailsAuth, RailsCsrf, RailsProxy, RequestURL}

  @routes [
    {"GET", "/users/password/new"},
    {"GET", "/users/password/edit"},
    {"GET", "/users/unlock/new"},
    {"GET", "/users/unlock"},
    {"POST", "/users/password"},
    {"POST", "/users/unlock"},
    {"PATCH", "/users/password"},
    {"PUT", "/users/password"}
  ]
  def init(opts), do: opts

  def route?(conn), do: {conn.method, conn.request_path} in @routes

  def call(conn, opts) do
    if Keyword.get(opts, :enabled, false) == true and route?(conn) and
         Admission.headers(conn.req_headers) == :ok do
      conn = conn |> DawarichWeb.HostAuthorization.call([]) |> DawarichWeb.ForceSSL.call([])
      if conn.halted, do: conn, else: admit(conn, opts)
    else
      fallback(conn, opts)
    end
  end

  defp admit(conn, opts) do
    conn = RailsAuth.call(conn, [])

    context =
      Keyword.get(opts, :context, %{})
      |> Map.merge(%{
        enabled: true,
        headers: conn.req_headers,
        sign_in_ip: to_string(:inet.ntoa(conn.remote_ip)),
        locale: DawarichWeb.Locale.resolve(nil, nil, conn.assigns.rails_session)
      })

    context =
      if Keyword.get(opts, :native, false) do
        context
        |> Map.put_new(:registration_enabled, false)
        |> Map.put_new(:enqueue, &Dawarich.Auth.Recovery.MailWorker.enqueue/1)
      else
        context
      end

    if not is_boolean(context[:registration_enabled]) or conn.assigns.current_user != nil or
         Enum.any?(get_req_header(conn, "accept"), &String.contains?(&1, "application/json")) or
         (not Keyword.get(opts, :native, false) and
            Admission.context(
              conn.assigns.rails_session,
              conn.req_headers,
              Map.get(context, :oidc, true),
              Map.get(context, :self_hosted, false)
            ) != :ok) do
      fallback(conn, opts)
    else
      parse(conn, opts, context)
    end
  end

  defp parse(%{method: "GET"} = conn, opts, context) do
    case decode(conn.query_string) do
      {:ok, params} -> dispatch(conn, conn.method, params, opts, context)
      _ -> fallback(conn, opts)
    end
  end

  defp parse(conn, opts, context) do
    with [length] <- get_req_header(conn, "content-length"),
         true <- length =~ ~r/\A\d+\z/ and String.to_integer(length) <= 65_536,
         [] <- get_req_header(conn, "transfer-encoding"),
         [type] <- get_req_header(conn, "content-type"),
         true <- hd(String.split(type, ";")) == "application/x-www-form-urlencoded",
         "" <- conn.query_string do
      case read_all(conn, []) do
        {:ok, raw, conn} ->
          conn = put_private(conn, :dawarich_raw_body, raw)

          with {:ok, params} <- decode(raw),
               {:ok, method} <- method(conn, params) do
            tokens = [params["authenticity_token"] | get_req_header(conn, "x-csrf-token")]

            if length(get_req_header(conn, "x-csrf-token")) <= 1 and origin?(conn) and
                 Enum.any?(
                   tokens,
                   &ActionCsrf.valid?(conn.assigns.rails_session, &1, method, conn.request_path)
                 ) do
              dispatch(conn, method, params, opts, context)
            else
              fallback(conn, opts)
            end
          else
            _ -> fallback(conn, opts)
          end

        {:error, _} ->
          conn |> send_resp(400, "") |> halt()
      end
    else
      _ -> fallback(conn, opts)
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

  defp dispatch(conn, method, params, opts, context) do
    flow = if Keyword.get(opts, :native, false), do: Dawarich.Auth.Recovery.Closure, else: Flow

    case flow.dispatch(method, conn.request_path, params, conn.assigns.rails_session, context) do
      {:ok, %{location: nil} = result} ->
        form(conn, result, context)

      {:ok, result} ->
        cookie =
          Map.get_lazy(result, :cookie, fn -> Flow.encode_session(result.session, context) end)

        conn
        |> AuthCookie.session({result.session, cookie})
        |> headers()
        |> put_resp_header("location", RequestURL.base(conn) <> result.location)
        |> send_resp(result.status, "")
        |> halt()

      {:error, :notification_owner} ->
        conn |> send_resp(503, "Security notifications unavailable") |> halt()

      {:error, {:delivery, _}} ->
        conn |> headers() |> send_resp(500, "Recovery delivery failed") |> halt()

      {:handoff, _} ->
        fallback(conn, opts)
    end
  end

  defp form(conn, result, context) do
    conn =
      conn
      |> fetch_query_params()
      |> DawarichWeb.Locale.call([])
      |> DawarichWeb.LayoutAssigns.call([])

    {session, _} =
      encoded =
      SessionCookie.for_form(
        result.session,
        Map.get_lazy(context, :secret, &Dawarich.RailsSecret.fetch/0)
      )

    token = RailsCsrf.masked_token(session)

    body =
      DawarichWeb.AuthRecovery.Form.render(
        result.view,
        token,
        result.assigns,
        conn.assigns.locale,
        context.registration_enabled
      )

    assigns =
      Map.merge(conn.assigns, %{
        __changed__: nil,
        flash: %{},
        page_title: nil,
        rails_csrf_token: token,
        inner_content: Phoenix.HTML.raw(body)
      })

    app = DawarichWeb.Layouts.app(assigns)

    html =
      DawarichWeb.Layouts.root(%{assigns | inner_content: app}) |> Phoenix.HTML.Safe.to_iodata()

    conn
    |> AuthCookie.session(encoded)
    |> headers()
    |> put_resp_content_type("text/html")
    |> send_resp(result.status, html)
    |> halt()
  end

  defp headers(conn),
    do:
      conn
      |> DawarichWeb.RailsHeaders.call([])
      |> put_resp_header("x-dawarich-auth-owner", "native-recovery")

  defp method(%{method: "POST", request_path: "/users/password"}, %{"_method" => "put"}),
    do: {:ok, "PUT"}

  defp method(%{method: "POST", request_path: "/users/password"}, %{"_method" => "patch"}),
    do: {:ok, "PATCH"}

  defp method(conn, params),
    do: if(Map.has_key?(params, "_method"), do: {:handoff, :method}, else: {:ok, conn.method})

  defp origin?(conn) do
    case get_req_header(conn, "origin") do
      [] -> true
      [origin] -> origin == RequestURL.base(conn)
      _ -> false
    end
  end

  defp decode(raw) when byte_size(raw) <= 65_536 do
    String.split(raw, "&", trim: true)
    |> Enum.reduce_while({:ok, %{}}, fn pair, {:ok, acc} ->
      with [key, value] <- String.split(pair, "=", parts: 2),
           false <- Regex.match?(~r/%(?![0-9a-fA-F]{2})/, pair),
           key <- URI.decode_www_form(key),
           value <- URI.decode_www_form(value),
           true <- String.valid?(key) and String.valid?(value),
           false <- Map.has_key?(acc, key) do
        {:cont, {:ok, Map.put(acc, key, value)}}
      else
        _ -> {:halt, {:handoff, :parameters}}
      end
    end)
  rescue
    ArgumentError -> {:handoff, :parameters}
  end

  defp decode(_), do: {:handoff, :parameters}

  defp fallback(conn, opts) do
    case {Keyword.get(opts, :native, false), Keyword.get(opts, :fallback)} do
      {true, _} -> conn |> send_resp(422, "Invalid recovery request") |> halt()
      {_, fun} when is_function(fun, 1) -> fun.(conn)
      _ -> RailsProxy.call(conn, Application.fetch_env!(:dawarich, :rails_upstream))
    end
  end
end
