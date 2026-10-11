defmodule DawarichWeb.AuthGate do
  @moduledoc false
  @behaviour Plug

  alias Dawarich.Auth.{Admission, RegistrationSetting}
  alias Dawarich.Auth.Recovery.MailWorker

  alias DawarichWeb.{
    AuthAccount,
    AuthHandler,
    AuthRecovery,
    AuthTwoFactor,
    AuthOtp,
    AuthAccountLink,
    AuthApi
  }

  @handlers [
    {"credentials", AuthHandler},
    {"recovery", AuthRecovery.Http},
    {"account", AuthAccount.Http},
    {"two_factor", AuthTwoFactor.Http},
    {"otp", AuthOtp.Http},
    {"account_link", AuthAccountLink.Http},
    {"api_auth", AuthApi.Http}
  ]

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn =
      DawarichWeb.StandaloneAuth.call(conn)

    case if(conn.halted, do: nil, else: claimed(conn)) do
      nil -> conn
      {flow, handler} -> handler.call(conn, native_options(flow, options(flow)))
    end
  end

  defp claimed(conn) do
    flows = flows()

    Enum.find(@handlers, fn {flow, handler} -> flow in flows and handler.route?(conn) end)
  end

  def flows, do: Enum.map(@handlers, &elem(&1, 0))

  defp native_options(_flow, opts), do: Keyword.put(opts, :native, true)

  defp options("account_link"),
    do: [enabled: true, context: Application.get_env(:dawarich, :account_link_context, %{})]

  defp options("api_auth"),
    do: [enabled: true, context: Application.get_env(:dawarich, :api_auth_context, %{})]

  defp options("otp"),
    do: [
      enabled: true,
      context: %{enqueue_otp_lock: &Dawarich.Mail.OtpAccountLockedWorker.enqueue/1}
    ]

  defp options(flow) when flow in ["account", "two_factor"],
    do: [enabled: true]

  defp options(flow), do: options(flow, RegistrationSetting.fetch())

  defp options("credentials", {:ok, registration}),
    do: [enabled: true, registration_enabled: registration, otp_enabled: otp_enabled?()]

  defp options("credentials", :error), do: [enabled: true, otp_enabled: otp_enabled?()]

  defp options("recovery", registration) do
    env = System.get_env()

    context =
      %{oidc: Admission.oidc?(env), self_hosted: env["SELF_HOSTED"] == "true"}
      |> put_registration(registration)
      |> put_enqueue(MailWorker.deliverable?(env))

    [enabled: true, context: context]
  end

  defp otp_enabled?, do: "otp" in flows()

  defp put_registration(context, {:ok, value}), do: Map.put(context, :registration_enabled, value)
  defp put_registration(context, :error), do: context

  defp put_enqueue(context, true), do: Map.put(context, :enqueue, &MailWorker.enqueue/1)
  defp put_enqueue(context, false), do: context
end
