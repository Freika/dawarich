defmodule Dawarich.Trips.AttachmentEditor do
  @moduledoc false
  alias Dawarich.Trips.Attachments

  def render(html, repo) do
    with {:ok, nodes} <- nodes(LazyHTML.from_fragment(html) |> LazyHTML.to_tree(), repo) do
      {:ok, LazyHTML.Tree.to_html(nodes)}
    end
  rescue
    _ -> :rails
  end

  defp nodes(tree, repo) do
    Enum.reduce_while(tree, {:ok, []}, fn node, {:ok, acc} ->
      case node(node, repo) do
        {:ok, converted} -> {:cont, {:ok, [converted | acc]}}
        _ -> {:halt, :rails}
      end
    end)
    |> case do
      {:ok, nodes} -> {:ok, Enum.reverse(nodes)}
      other -> other
    end
  end

  defp node({"action-text-attachment", attrs, _}, repo) do
    with {:ok, attrs} <- attributes(attrs, repo) do
      data = Map.new(attrs, &attribute/1)
      composed = Map.take(data, ~w(caption presentation))
      attrs = [{"data-trix-attachment", Jason.encode!(Map.drop(data, ~w(caption presentation)))}]

      attrs =
        if map_size(composed) > 0,
          do: attrs ++ [{"data-trix-attributes", Jason.encode!(composed)}],
          else: attrs

      {:ok, {"figure", attrs, []}}
    end
  end

  defp node({tag, attrs, children}, repo) do
    with {:ok, children} <- nodes(children, repo), do: {:ok, {tag, attrs, children}}
  end

  defp node(node, _repo), do: {:ok, node}

  defp attributes(attrs, repo) do
    case List.keyfind(attrs, "sgid", 0) do
      {_, sgid} ->
        case Attachments.resolve(repo, sgid) do
          {:ok, blob} -> {:ok, Attachments.attributes(blob, attrs)}
          status when status in [:missing, :invalid] -> {:ok, attrs}
          _ -> :rails
        end

      nil ->
        {:ok, attrs}
    end
  end

  defp attribute({key, value}) do
    key = if key == "content-type", do: "contentType", else: key

    value =
      case key do
        "previewable" -> value == "true"
        "filesize" -> integer(value) || value
        key when key in ~w(width height) -> integer(value)
        _ -> value
      end

    {key, value}
  end

  defp integer(value) do
    value = Regex.replace(~r/\A[\t\n\x0B\f\r ]*|[\t\n\x0B\f\r ]*\z/, value, "")

    case Regex.run(
           ~r/\A([+-]?)(0[xX]|0[bB]|0[oO]|0[dD])?([0-9a-fA-F](?:_?[0-9a-fA-F])*)\z/,
           value
         ) do
      [_, sign, prefix, digits] ->
        base =
          case String.downcase(prefix) do
            "0x" -> 16
            "0b" -> 2
            "0o" -> 8
            "0d" -> 10
            "" -> if String.starts_with?(digits, "0"), do: 8, else: 10
          end

        case Integer.parse(String.replace(digits, "_", ""), base) do
          {number, ""} -> if sign == "-", do: -number, else: number
          _ -> nil
        end

      _ ->
        nil
    end
  end
end
