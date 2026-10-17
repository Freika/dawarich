defmodule Dawarich.Mail.SmtpConfig do
  @moduledoc false
  @speakable ~w(plain login cram_md5 xoauth2)
  @no_auth ~w(none nil false off disabled)

  def admitted?(env) do
    configured = options(env)
    Dawarich.Standalone.enabled?(env) or configured[:auth_mechanism] != "xoauth2"
  end

  def options(env) do
    authenticate?(env)

    if blank?(env["SMTP_SERVER"]) and not blank?(env["E2E_SMTP_PORT"]),
      do: sink(env),
      else: server(env)
  end

  defp sink(env) do
    if (authenticate?(env) and
          (Map.has_key?(env, "SMTP_AUTHENTICATION") or not blank?(env["SMTP_USERNAME"]) or
             not blank?(env["SMTP_PASSWORD"]))) or
         String.trim(env["SMTP_SSL"] || "") == "true" or env["SMTP_STARTTLS"] == "true" do
      raise ArgumentError,
            "E2E SMTP sink cannot enforce configured authentication or TLS; configure SMTP_SERVER"
    end

    [
      relay: ~c"127.0.0.1",
      port: String.to_integer(env["E2E_SMTP_PORT"]),
      ssl: false,
      tls: :never,
      auth: :never,
      retries: 0,
      timeout: 60_000
    ]
  end

  def envelope_from(from) do
    case Regex.run(~r/<([^>]+)>/, from || "") do
      [_, address] -> address
      _ -> String.trim(from || "")
    end
  end

  defp server(env) do
    ssl = ssl?(env)
    auth? = authenticate?(env)
    relay = String.to_charlist(env["SMTP_SERVER"] || "")
    certificate_options = tls_options(env, relay)

    [
      relay: relay,
      hostname:
        String.to_charlist(
          if(blank?(env["SMTP_DOMAIN"]), do: "localhost", else: env["SMTP_DOMAIN"])
        ),
      ssl: ssl,
      tls: if(not ssl and (env["SMTP_STARTTLS"] || "true") == "true", do: :always, else: :never),
      auth: if(auth?, do: :always, else: :never),
      retries: 0,
      timeout: seconds(env["SMTP_READ_TIMEOUT"], 60) * 1_000,
      tls_options: certificate_options,
      sockopts: if(ssl, do: certificate_options, else: [])
    ] ++ port(env["SMTP_PORT"]) ++ credentials(env, auth?) ++ auth_policy(env, auth?)
  end

  defp authenticate?(env) do
    raw = (env["SMTP_AUTHENTICATION"] || "plain") |> String.trim() |> String.downcase()

    cond do
      raw == "" or raw in @speakable ->
        true

      raw in @no_auth ->
        false

      true ->
        raise ArgumentError,
              "SMTP_AUTHENTICATION=#{raw}: native mail refuses delivery because the mechanism is unsupported; " <>
                "no authentication or TLS fallback; supported selections are plain, login, cram_md5, xoauth2 or none"
    end
  end

  defp auth_policy(_env, false), do: []

  defp auth_policy(env, true) do
    selected = (env["SMTP_AUTHENTICATION"] || "plain") |> String.trim() |> String.downcase()
    selected = if selected == "", do: "plain", else: selected
    [auth_mechanism: selected]
  end

  defp ssl?(env) do
    case String.trim(env["SMTP_SSL"] || "") do
      "" -> port(env["SMTP_PORT"]) == [port: 465]
      raw -> raw == "true"
    end
  end

  defp tls_options(env, relay) do
    case (env["SMTP_OPENSSL_VERIFY_MODE"] || "") |> String.trim() |> String.downcase() do
      "none" ->
        [verify: :verify_none]

      mode when mode in ["", "peer"] ->
        [
          verify: :verify_peer,
          server_name_indication: relay,
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ] ++ trust_options(env)

      mode ->
        raise ArgumentError,
              "SMTP_OPENSSL_VERIFY_MODE=#{mode} is not supported; expected none or peer"
    end
  end

  defp trust_options(env) do
    if blank?(env["SMTP_CA_FILE"]),
      do: [cacerts: :public_key.cacerts_get()],
      else: [cacertfile: String.to_charlist(env["SMTP_CA_FILE"])]
  end

  defp credentials(env, true),
    do: [
      username: String.to_charlist(env["SMTP_USERNAME"] || ""),
      password: String.to_charlist(env["SMTP_PASSWORD"] || "")
    ]

  defp credentials(_env, false), do: []

  defp port(value) do
    case Integer.parse(String.trim(value || "")) do
      {port, _} -> [port: port]
      :error -> []
    end
  end

  defp seconds(value, default) do
    case Integer.parse(String.trim(value || "")) do
      {seconds, _} -> seconds
      :error -> default
    end
  end

  defp blank?(value), do: value in [nil, ""] or String.trim(value) == ""
end
