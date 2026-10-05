defmodule DawarichWeb.AuthApi.Input do
  @moduledoc false
  import Plug.Conn
  alias DawarichWeb.Api.Body
  @fields %{login: ~w(email password), challenge: ~w(challenge_token otp_code)}
  @content_type ~r/\A(?:application\/json|text\/x-json|application\/jsonrequest|application\/x-www-form-urlencoded)(?:;\s*charset=utf-8)?\z/i

  def precheck(conn) do
    names = Enum.map(conn.req_headers, &elem(&1, 0))

    with true <- conn.query_string == "",
         true <- length(names) == length(Enum.uniq(names)),
         false <- Enum.any?(names, &String.contains?(&1, "_")),
         [] <- get_req_header(conn, "transfer-encoding"),
         [] <- get_req_header(conn, "x-http-method-override"),
         [length] <- get_req_header(conn, "content-length"),
         true <- Regex.match?(~r/\A[0-9]{1,5}\z/, length) and String.to_integer(length) <= 16_384,
         [type] <- get_req_header(conn, "content-type"),
         true <- Regex.match?(@content_type, type) do
      :ok
    else
      _ -> {:replay, :input_headers}
    end
  end

  def select(conn, action) do
    with :ok <- precheck(conn),
         raw when is_binary(raw) <- conn.private[:dawarich_raw_body],
         true <-
           String.valid?(raw) and
             byte_size(raw) == String.to_integer(hd(get_req_header(conn, "content-length"))),
         {:ok, pairs} <- pairs(conn, raw),
         true <- unique?(pairs),
         true <-
           Enum.all?(pairs, fn {key, value} ->
             key in Map.fetch!(@fields, action) and (is_nil(value) or is_binary(value))
           end) do
      {:ok, Map.new(pairs)}
    else
      _ -> {:replay, :input_shape}
    end
  rescue
    _ in [ArgumentError, KeyError] -> {:replay, :input_shape}
  end

  defp pairs(conn, raw) do
    case Body.kind(conn) do
      :json ->
        case Jason.decode(raw, objects: :ordered_objects) do
          {:ok, %Jason.OrderedObject{values: pairs}} -> {:ok, pairs}
          _ -> :invalid
        end

      :form ->
        if Regex.match?(~r/%(?![0-9A-Fa-f]{2})/, raw), do: :invalid, else: Body.segments(raw)

      _ ->
        :invalid
    end
  end

  defp unique?(pairs) do
    keys = Enum.map(pairs, &elem(&1, 0))
    length(keys) == length(Enum.uniq(keys))
  end
end
