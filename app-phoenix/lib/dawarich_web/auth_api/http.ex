defmodule DawarichWeb.AuthApi.Http do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.{Accounts, UserTimeZone}
  alias Dawarich.Auth.Admission
  alias Dawarich.Auth.Api.{Challenge, ChallengeToken, ChallengeWrite, Login}
  alias DawarichWeb.{HostAuthorization, ForceSSL, RailsProxy, RateLimit}
  alias DawarichWeb.Api.{Auth, Body}
  alias DawarichWeb.AuthApi.{Input, Response}
  @routes %{"/api/v1/auth/login" => :login, "/api/v1/auth/otp_challenge" => :challenge}

  def init(opts), do: opts
  def route?(conn), do: conn.method == "POST" and Map.has_key?(@routes, conn.request_path)

  def call(conn, opts) do
    if Keyword.get(opts, :standalone, Dawarich.Standalone.enabled?()) and
         Keyword.get(opts, :enabled, false) do
      DawarichWeb.AuthMobile.Http.call(conn, opts)
    else
      coexist(conn, opts)
    end
  end

  defp coexist(conn, opts) do
    env = Keyword.get(opts, :context, %{}) |> Map.get_lazy(:env, &System.get_env/0)

    context =
      Keyword.get(opts, :context, %{})
      |> Map.put_new(:self_hosted, System.get_env("SELF_HOSTED") == "true")
      |> Map.put_new(:oidc, Admission.oidc?(env))

    if Keyword.get(opts, :enabled, false) and route?(conn) and
         context.self_hosted == true and context.oidc != true do
      conn = conn |> assign(:api_tag, "api") |> HostAuthorization.call([])
      if conn.halted, do: conn, else: ssl(conn, opts, context)
    else
      fallback(conn, opts)
    end
  end

  defp ssl(conn, opts, context) do
    conn = ForceSSL.call(conn, [])
    if conn.halted, do: conn, else: rate(conn, opts, context)
  end

  defp rate(conn, opts, context) do
    conn = RateLimit.call(conn, [])
    if conn.halted, do: conn, else: parse(conn, opts, context)
  end

  defp parse(conn, opts, context) do
    conn = fetch_cookies(conn)

    if Input.precheck(conn) == :ok and stateless?(conn) do
      conn = Body.call(conn, [])

      if conn.halted do
        if conn.state == :unset, do: conn |> send_resp(400, "") |> halt(), else: conn
      else
        public(conn, opts, context)
      end
    else
      fallback(conn, opts)
    end
  end

  defp stateless?(conn) do
    not Map.has_key?(conn.cookies, "_dawarich_session") and
      not Map.has_key?(conn.cookies, "remember_user_token") and
      Enum.all?(
        ~w(x-dawarich-client x-requested-with x-csrf-token origin x-forwarded-for client-ip forwarded),
        &(get_req_header(conn, &1) == [])
      )
  end

  defp public(conn, opts, context) do
    conn = Auth.public(conn)
    if conn.halted, do: conn, else: select(conn, opts, context)
  end

  defp select(conn, opts, context) do
    action = Map.fetch!(@routes, conn.request_path)

    with true <- conn.assigns.api_format in [:json, :html, :all],
         {:ok, params} <- Input.select(conn, action),
         {:ok, context} <- caller_context(conn, context) do
      execute(conn, opts, action, params, context)
    else
      _ -> fallback(conn, opts)
    end
  end

  defp caller_context(conn, context) do
    key =
      case get_req_header(conn, "authorization") do
        [value] ->
          case Regex.run(~r/\ABearer\s+(\S+)\z/i, value, capture: :all_but_first) do
            [key] -> key
            _ -> nil
          end

        _ ->
          nil
      end

    case key && Accounts.by_api_key(key) do
      %{timezone: timezone} when is_binary(timezone) or is_nil(timezone) ->
        zone = UserTimeZone.name(%{"timezone" => timezone})
        {:ok, Map.put(context, :timezone, zone)}

      nil ->
        {:ok, context}

      _ ->
        {:replay, :caller_metadata}
    end
  rescue
    _ in [Postgrex.Error, ArgumentError] -> {:replay, :caller_metadata}
  end

  defp execute(conn, opts, :login, params, context) do
    case Login.prepare(params["email"], params["password"], context) do
      {:success, _user, payload} ->
        :ok = Response.preflight(conn, payload)
        Response.success(conn, payload)

      {:challenge, user} ->
        case ChallengeToken.issue(user.id, context) do
          {:ok, token} ->
            :ok = Response.preflight(conn, Response.challenge_term(token))
            Response.challenge(conn, token)

          _ ->
            fallback(conn, opts)
        end

      _ ->
        fallback(conn, opts)
    end
  end

  defp execute(conn, opts, :challenge, params, context) do
    case Challenge.prepare(params["challenge_token"], params["otp_code"], context) do
      {:ok, prepared} ->
        :ok = Response.preflight(conn, prepared.payload)
        {:ok, payload} = ChallengeWrite.commit(prepared, context)
        Response.success(conn, payload)

      _ ->
        fallback(conn, opts)
    end
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
