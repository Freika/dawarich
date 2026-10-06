defmodule DawarichWeb.AuthMobile.Http do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias DawarichWeb.AuthApi.{Input, Response}
  alias DawarichWeb.Api.Headers
  alias Dawarich.Auth.Api.Refusals

  @actions ~w(login otp_challenge register google apple)
  def init(opts), do: opts

  def route?(conn),
    do:
      conn.method == "POST" and String.starts_with?(conn.request_path, "/api/v1/auth/") and
        length(String.split(conn.request_path, "/")) == 5 and action(conn) in @actions

  def call(conn, opts) do
    if Keyword.get(opts, :enabled, false) and route?(conn) do
      conn = conn |> DawarichWeb.HostAuthorization.call([]) |> DawarichWeb.ForceSSL.call([])
      conn = if conn.halted, do: conn, else: DawarichWeb.RateLimit.call(conn, [])
      if conn.halted, do: conn, else: execute(conn, opts)
    else
      conn
    end
  end

  defp execute(conn, opts) do
    context = Keyword.get(opts, :context, %{})
    env = Map.get_lazy(context, :env, &System.get_env/0)

    context =
      context
      |> Map.put_new(:self_hosted, Dawarich.ReleaseMigration.self_hosted?(env))
      |> Map.put_new(:oidc, Dawarich.Auth.Admission.oidc?(env))
      |> Map.put_new(:base_url, DawarichWeb.RequestURL.base(conn))

    conn = frame(conn)

    case Input.native(conn) do
      {:ok, params, conn} ->
        {conn, context} = caller(conn, params, context)
        result = dispatch(action(conn), params, context)
        Response.result(conn, result, context)

      {:error, conn} ->
        Response.reply(conn, 400, {:object, [{"error", "invalid_request"}]})
    end
  rescue
    _ ->
      conn = frame(conn)
      Response.reply(conn, 503, {:object, [{"error", "authentication_unavailable"}]})
  end

  defp dispatch("login", params, context), do: Refusals.login(params, context)
  defp dispatch("otp_challenge", params, context), do: Refusals.challenge(params, context)

  defp dispatch("register", params, context),
    do: Dawarich.Auth.Mobile.Registration.create(params, context)

  defp dispatch(provider, params, context) when provider in ["apple", "google"],
    do: Dawarich.Auth.Mobile.Providers.exchange(provider, params, context)

  defp dispatch(action, _params, _context),
    do: {:error, 422, %{"error" => action <> "_unavailable"}}

  def frame(conn) do
    conn
    |> assign(:api_tag, "api")
    |> assign(:api_started, System.monotonic_time())
    |> assign(:api_request_id, Ecto.UUID.generate())
    |> assign(:api_headers, Headers.dawarich(false, Dawarich.AppVersion.current()))
    |> assign(:api_vary, true)
    |> assign(:api_if_none_match, nil)
  end

  defp caller(conn, params, context) do
    key =
      params["api_key"] ||
        case get_req_header(conn, "authorization") do
          ["Bearer " <> value] -> value
          _ -> nil
        end

    user = if is_binary(key), do: Dawarich.Accounts.by_api_key(key)

    context =
      if user,
        do:
          Map.put(context, :timezone, Dawarich.UserTimeZone.name(%{"timezone" => user.timezone})),
        else: context

    {assign(conn, :api_headers, Headers.dawarich(user != nil, Dawarich.AppVersion.current())),
     context}
  end

  defp action(conn),
    do:
      conn.request_path
      |> String.replace(~r/\.(json|html)\z/, "")
      |> String.split("/")
      |> List.last()
end
