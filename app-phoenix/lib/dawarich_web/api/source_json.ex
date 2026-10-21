defmodule DawarichWeb.Api.SourceJSON do
  @moduledoc false

  def decode(raw) do
    raw
    |> scan(:plain, [])
    |> Jason.decode(objects: :ordered_objects)
  catch
    :invalid_comment -> {:error, :invalid_comment}
  end

  defp scan(<<>>, mode, acc) when mode in [:plain, :line],
    do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp scan(<<>>, _mode, _acc), do: throw(:invalid_comment)
  defp scan(<<"/*", rest::binary>>, :plain, acc), do: scan(rest, :block, [" " | acc])
  defp scan(<<"//", rest::binary>>, :plain, acc), do: scan(rest, :line, [" " | acc])
  defp scan(<<"*/", rest::binary>>, :block, acc), do: scan(rest, :plain, acc)
  defp scan(<<_byte, rest::binary>>, :block, acc), do: scan(rest, :block, acc)

  defp scan(<<byte, rest::binary>>, :line, acc) when byte in [10, 13],
    do: scan(rest, :plain, [<<byte>> | acc])

  defp scan(<<_byte, rest::binary>>, :line, acc), do: scan(rest, :line, acc)

  defp scan(<<"\\", byte, rest::binary>>, :string, acc),
    do: scan(rest, :string, [<<92, byte>> | acc])

  defp scan(<<34, rest::binary>>, :string, acc), do: scan(rest, :plain, [<<34>> | acc])
  defp scan(<<34, rest::binary>>, :plain, acc), do: scan(rest, :string, [<<34>> | acc])
  defp scan(<<byte, rest::binary>>, mode, acc), do: scan(rest, mode, [<<byte>> | acc])
end
