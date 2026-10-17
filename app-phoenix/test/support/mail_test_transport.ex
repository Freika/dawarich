defmodule Dawarich.Mail.TestTransport do
  @moduledoc false

  def result(row) do
    host = ~c"synthetic.test"

    reason =
      case row["id"] do
        "socket_error" ->
          {:network_failure, host, {:error, :nxdomain}}

        "timeout_error" ->
          {:network_failure, host, {:error, :timeout}}

        "ssl_error" ->
          {:temporary_failure, host, :tls_failed}

        "system_error" ->
          {:network_failure, host, {:error, :econnrefused}}

        "smtp_error" ->
          {:permanent_failure, host, :auth_failed}

        "smtp_busy" ->
          {:temporary_failure, host, "451 try later\r\n"}

        "smtp_syntax" ->
          {:permanent_failure, host, "501 invalid command\r\n"}

        "smtp_auth_reply" ->
          {:permanent_failure, host, "535 denied\r\n"}

        "smtp_unknown" ->
          {:unexpected_response, host, "399 unexpected\r\n"}

        "smtp_multiline" ->
          {:permanent_failure, host, "550-first line\r\n550 second line\r\n"}

        id when id in ["smtp_fatal", "turbo_smtp_fatal"] ->
          {:permanent_failure, host, "550 rejected\r\n"}

        _ ->
          nil
      end

    cond do
      row["id"] == "argument_error" -> {:error, :invalid_port}
      reason -> {:error, {:send, reason}}
      row["transport_error"] -> {:error, :unclassified_failure}
      true -> :ok
    end
  end

  def deliver(message, _env) do
    send(self(), {:mail, message})

    if watcher = Process.get(:hang_in_transport) do
      send(watcher, {:in_transport, message})
      Process.sleep(:infinity)
    end

    if Process.get(:crash_after_send), do: raise("crashed after the server accepted the message")
    Process.get(:transport_result, :ok)
  end
end
