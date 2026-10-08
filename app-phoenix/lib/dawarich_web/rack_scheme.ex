defmodule DawarichWeb.RackScheme do
  @moduledoc false

  @allowed ~w(https http wss ws)
  @params ~w(by for host proto)
  @limit 1024
  @separators ~r/\A[\s;,]+/

  def ssl?(conn), do: scheme(conn) in ["https", "wss"]

  defp scheme(%{scheme: :https}), do: "https"

  defp scheme(conn) do
    cond do
      header(conn, "x-forwarded-ssl") == "on" -> "https"
      scheme = forwarded_scheme(conn) -> scheme
      true -> Atom.to_string(conn.scheme)
    end
  end

  defp forwarded_scheme(conn) do
    forwarded_proto(header(conn, "forwarded")) ||
      last_allowed(header(conn, "x-forwarded-proto")) ||
      last_allowed(header(conn, "x-forwarded-scheme"))
  end

  defp header(conn, name) do
    case Plug.Conn.get_req_header(conn, name) do
      [] -> nil
      values -> Enum.join(values, ", ")
    end
  end

  defp forwarded_proto(value) do
    case forwarded_values(value) do
      %{"proto" => protos} -> if List.last(protos) in @allowed, do: List.last(protos)
      _ -> nil
    end
  end

  defp last_allowed(nil), do: nil

  defp last_allowed(value) do
    value
    |> strip()
    |> String.split(~r/[, \t]+/)
    |> Enum.reverse()
    |> Enum.find(&(&1 in @allowed))
  end

  def forwarded_values(nil), do: nil

  def forwarded_values(value) do
    value |> String.replace("\n", ";") |> String.replace(@separators, "") |> params(%{}, 0, 0)
  end

  defp params(header, params, count, escapes) do
    case :binary.match(header, "=") do
      :nomatch ->
        params

      {i, 1} when count < @limit ->
        <<name::binary-size(^i), "=", rest::binary>> = header
        name = name |> strip() |> String.downcase()

        with true <- name in @params,
             {value, rest, escapes} <- value(rest, escapes) do
          rest = String.replace(rest, @separators, "")
          params(rest, Map.update(params, name, [value], &(&1 ++ [value])), count + 1, escapes)
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp value(<<?", rest::binary>>, escapes), do: quoted(rest, "", escapes)

  defp value(rest, escapes) do
    case :binary.match(rest, [";", ","]) do
      {i, 1} ->
        <<value::binary-size(^i), tail::binary>> = rest
        {strip(value), tail, escapes}

      :nomatch ->
        {strip(rest), "", escapes}
    end
  end

  defp quoted(rest, acc, escapes) do
    case :binary.match(rest, ["\"", "\\"]) do
      :nomatch ->
        {acc, rest, escapes}

      {i, 1} ->
        case rest do
          <<chunk::binary-size(^i), ?", tail::binary>> ->
            {acc <> chunk, tail, escapes}

          _ when escapes >= @limit ->
            nil

          <<chunk::binary-size(^i), ?\\, char::binary-size(1), tail::binary>> ->
            quoted(tail, acc <> chunk <> char, escapes + 1)

          <<chunk::binary-size(^i), ?\\>> ->
            {acc <> chunk, "", escapes + 1}
        end
    end
  end

  defp strip(value), do: String.replace(value, ~r/\A\s+|\s+\z/, "")
end
