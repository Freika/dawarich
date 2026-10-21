defmodule Dawarich.Imports.Geometry.Wkt do
  @moduledoc false
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @types %{
    "point" => "POINT",
    "linestring" => "LINESTRING",
    "polygon" => "POLYGON",
    "multipoint" => "MULTIPOINT",
    "multilinestring" => "MULTILINESTRING",
    "multipolygon" => "MULTIPOLYGON",
    "geometrycollection" => "GEOMETRYCOLLECTION"
  }
  @number ~r/\A[-+]?(\d+(\.\d*)?|\.\d+)(e[-+]?\d+)?\z/
  @word ~r/\A[a-z]+\z/

  def parse(text) do
    with {:ok, tokens} <- tokenize(text |> String.downcase() |> without_srid()),
         {:ok, geometry, []} <- tag(tokens) do
      result(geometry)
    else
      _ -> :error
    end
  catch
    :error -> :error
  end

  defp result({"POINT", [x, y]}), do: {:point, x, y}
  defp result({"POINT", :empty}), do: :empty_point
  defp result(geometry), do: {:other, geometry}

  defp without_srid(text) do
    case Regex.run(~r/^srid=\d+;/m, text, return: :index) do
      [{start, length}] -> binary_part(text, start + length, byte_size(text) - start - length)
      nil -> text
    end
  end

  defp tokenize(text) do
    tokens =
      Regex.scan(~r/\(|\)|\[|\]|,|[^\s()\[\],]+/, text)
      |> Enum.map(fn [token] -> token(token) end)

    {:ok, tokens}
  end

  defp token(token) when token in ["(", "["], do: :begin
  defp token(token) when token in [")", "]"], do: :end
  defp token(","), do: :comma

  defp token(token) do
    cond do
      Regex.match?(@number, token) -> {:number, Ruby.to_f(token)}
      Regex.match?(@word, token) -> {:word, token}
      true -> throw(:error)
    end
  end

  defp tag([{:word, word} | rest]) do
    with false <- byte_size(word) > 1 and String.ends_with?(word, "m"),
         {:ok, type} <- Map.fetch(@types, word) do
      shape(type, rest)
    else
      _ -> :error
    end
  end

  defp tag(_tokens), do: :error

  defp shape(type, [{:word, "empty"} | rest]), do: {:ok, {type, :empty}, rest}

  defp shape("POINT", [:begin | rest]), do: rest |> coords() |> close()
  defp shape("LINESTRING", tokens), do: line(tokens)
  defp shape("POLYGON", tokens), do: list(tokens, "POLYGON", &line/1)
  defp shape("MULTIPOINT", tokens), do: list(tokens, "MULTIPOINT", &member_point/1)
  defp shape("MULTILINESTRING", tokens), do: list(tokens, "MULTILINESTRING", &line/1)
  defp shape("MULTIPOLYGON", tokens), do: list(tokens, "MULTIPOLYGON", &polygon/1)
  defp shape("GEOMETRYCOLLECTION", tokens), do: list(tokens, "GEOMETRYCOLLECTION", &tag/1)
  defp shape(_type, _tokens), do: :error

  defp line([{:word, "empty"} | rest]), do: {:ok, {"LINESTRING", :empty}, rest}
  defp line(tokens), do: list(tokens, "LINESTRING", &coords/1)

  defp polygon([{:word, "empty"} | rest]), do: {:ok, {"POLYGON", :empty}, rest}
  defp polygon(tokens), do: list(tokens, "POLYGON", &line/1)

  defp member_point([:begin | rest]), do: rest |> coords() |> close()
  defp member_point(tokens), do: coords(tokens)

  defp list([:begin | rest], type, item), do: items(rest, type, item, [])
  defp list(_tokens, _type, _item), do: :error

  defp items(tokens, type, item, acc) do
    case item.(tokens) do
      {:ok, value, [:end | rest]} -> {:ok, {type, Enum.reverse([value | acc])}, rest}
      {:ok, value, [:comma | rest]} -> items(rest, type, item, [value | acc])
      _ -> :error
    end
  end

  defp coords([{:number, x}, {:number, y} | rest]) do
    case rest do
      [{:number, _} | _] -> :error
      _ -> {:ok, [x, y], rest}
    end
  end

  defp coords(_tokens), do: :error

  defp close({:ok, [x, y], [:end | rest]}), do: {:ok, {"POINT", [x, y]}, rest}
  defp close(_result), do: :error
end
