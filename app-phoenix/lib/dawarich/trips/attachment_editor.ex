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
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end
end
