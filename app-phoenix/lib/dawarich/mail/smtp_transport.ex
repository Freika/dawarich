defmodule Dawarich.Mail.SmtpTransport do
  @moduledoc false
  alias Dawarich.Mail.SmtpAuthentication

  def send(envelope, options) do
    timeout = options[:timeout]
    protocol = if options[:ssl], do: :ssl, else: :tcp
    port = options[:port] || if(options[:ssl], do: 465, else: 25)

    case :smtp_socket.connect(
           protocol,
           options[:relay],
           port,
           [:binary | options[:sockopts]],
           timeout
         ) do
      {:ok, socket} ->
        try do
          expect(socket, 220, timeout)
          extensions = hello(socket, options)
          session(socket, extensions, envelope, options)
        catch
          {:smtp_failure, type, reason} -> failure(options, type, reason)
        after
          :smtp_socket.close(socket)
        end

      {:error, reason} ->
        failure(options, :network_failure, {:error, reason})
    end
  end

  defp session(socket, extensions, envelope, options) do
    if options[:tls] == :always do
      unless Enum.any?(extensions, &(String.upcase(String.trim(&1)) == "STARTTLS")),
        do: throw({:smtp_failure, :missing_requirement, :tls})

      command(socket, "STARTTLS", 220, options[:timeout])

      case :smtp_socket.to_ssl_client(
             socket,
             [:binary | options[:tls_options]],
             options[:timeout]
           ) do
        {:ok, secure} ->
          try do
            hello(secure, options)
            authenticated_delivery(secure, envelope, options)
          after
            :smtp_socket.close(secure)
          end

        {:error, _} ->
          throw({:smtp_failure, :temporary_failure, :tls_failed})
      end
    else
      authenticated_delivery(socket, envelope, options)
    end
  end

  defp authenticated_delivery(socket, {from, recipients, body}, options) do
    SmtpAuthentication.authenticate(socket, options)
    timeout = options[:timeout]
    command(socket, "MAIL FROM:<#{from}>", 250, timeout)
    for recipient <- recipients, do: command(socket, "RCPT TO:<#{recipient}>", 200..299, timeout)
    command(socket, "DATA", 354, timeout)
    escaped = Regex.replace(~r/^\./m, body, "..")
    write(socket, [escaped, "\r\n.\r\n"])
    receipt = expect(socket, 250, timeout) |> Enum.join("\r\n")
    :smtp_socket.send(socket, "QUIT\r\n")
    receipt
  end

  defp hello(socket, options) do
    write(socket, ["EHLO ", options[:hostname], "\r\n"])

    case reply(socket, options[:timeout]) do
      {250, extensions} ->
        extensions

      {code, _} when code in [500, 502, 504] ->
        command(socket, "HELO #{options[:hostname]}", 250, options[:timeout])
        []

      {code, _} ->
        rejected(code)
    end
  end

  def command(socket, line, code, timeout) do
    write(socket, [line, "\r\n"])
    expect(socket, code, timeout)
  end

  defp expect(socket, code, timeout) do
    codes = if is_integer(code), do: [code], else: code
    {status, lines} = reply(socket, timeout)
    if status in codes, do: lines, else: rejected(status)
  end

  def reply(socket, timeout), do: reply(socket, timeout, nil, [])

  defp reply(socket, timeout, expected, lines) do
    case :smtp_socket.recv(socket, 0, timeout) do
      {:ok, line} ->
        {code, separator, text} = reply_line(line)

        if expected in [nil, code] do
          lines = [String.trim_trailing(text) | lines]

          if separator == "-",
            do: reply(socket, timeout, code, lines),
            else: {code, Enum.reverse(lines)}
        else
          throw({:smtp_failure, :permanent_failure, :invalid_reply})
        end

      {:error, reason} ->
        throw({:smtp_failure, :network_failure, {:error, reason}})

      _ ->
        throw({:smtp_failure, :permanent_failure, :invalid_reply})
    end
  end

  defp reply_line(line) do
    case Regex.run(~r/\A([0-9]{3})([ -]?)([^\r\n]*)\r?\n?\z/, line, capture: :all_but_first) do
      [digits, separator, text] when separator in [" ", "-"] or text == "" ->
        {String.to_integer(digits), separator, text}

      _ ->
        throw({:smtp_failure, :permanent_failure, :invalid_reply})
    end
  end

  defp write(socket, data) do
    case :smtp_socket.send(socket, data) do
      :ok -> :ok
      {:error, reason} -> throw({:smtp_failure, :network_failure, {:error, reason}})
    end
  end

  defp rejected(code),
    do:
      throw(
        {:smtp_failure, if(code in 400..499, do: :temporary_failure, else: :permanent_failure),
         {:smtp_status, code}}
      )

  defp failure(options, type, reason) do
    category = if type == :permanent_failure, do: :no_more_hosts, else: :retries_exceeded
    {:error, category, {type, options[:relay], reason}}
  end
end
