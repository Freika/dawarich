defmodule DawarichWeb.PageAccept do
  @moduledoc false

  @types ~w(text/html text/plain text/javascript text/css text/calendar text/csv text/vcard text/vtt text/markdown image/png image/jpeg image/gif image/bmp image/tiff image/svg+xml image/webp video/mpeg audio/mpeg audio/ogg audio/aac video/webm video/mp4 font/otf font/ttf font/woff font/woff2 application/xml application/rss+xml application/atom+xml application/x-yaml multipart/form-data application/x-www-form-urlencoded application/json application/pdf application/zip application/gzip text/vnd.turbo-stream.html application/geo+json application/manifest+json)
  @aliases %{
    "application/xhtml+xml" => "text/html",
    "application/javascript" => "text/javascript",
    "application/x-javascript" => "text/javascript",
    "audio/mp4" => "audio/aac",
    "text/xml" => "application/xml",
    "application/x-xml" => "application/xml",
    "text/yaml" => "application/x-yaml",
    "text/x-json" => "application/json",
    "application/jsonrequest" => "application/json",
    "application/problem+json" => "application/json",
    "application/x-gzip" => "application/gzip"
  }

  def formats(accept, xhr?) do
    cond do
      String.trim(accept) == "" ->
        [if(xhr?, do: "text/javascript", else: "text/html")]

      not xhr? and DawarichWeb.Strangler.browser_like?(accept) ->
        ["text/html"]

      true ->
        parse(accept)
    end
  end

  defp parse(accept) do
    items =
      if String.contains?(accept, ",") do
        Regex.scan(~r/[^,\s"](?:[^,"]|"[^"]*")*/, accept)
        |> Enum.flat_map(fn [header] ->
          [name | rest] = Regex.split(~r/;\s*q="?/, header)
          name = String.trim(name)
          q = quality(List.first(rest), name)
          for type <- expand(name), do: {type, q}
        end)
        |> Enum.with_index()
        |> Enum.sort_by(fn {{_type, q}, index} -> {-q, index} end)
        |> Enum.map(fn {item, _index} -> item end)
        |> xml_order()
      else
        name = Regex.split(~r/;\s*q="?/, accept) |> hd() |> String.trim()
        for type <- expand(name), do: {type, 100}
      end

    items
    |> Enum.map(fn {name, _q} -> canonical(name) end)
    |> Enum.filter(&(&1 in @types or &1 == "*/*"))
    |> Enum.uniq()
  end

  defp expand(""), do: []

  defp expand(name) do
    case Regex.run(~r/^(text|application)\/\*/, name) do
      [_, family] ->
        prefix = family <> "/"

        Enum.filter(@types, fn type ->
          String.starts_with?(type, prefix) or
            Enum.any?(@aliases, fn {other, target} ->
              target == type and String.starts_with?(other, prefix)
            end)
        end)

      _ ->
        [name]
    end
  end

  defp canonical(name) do
    type = name |> String.split(";", parts: 2) |> hd() |> String.trim_trailing()
    Map.get(@aliases, type, type)
  end

  defp quality(nil, "*/*"), do: 0
  defp quality(nil, _name), do: 100

  defp quality(text, _name) do
    case Float.parse(String.trim_leading(text)) do
      {value, _} -> trunc(value * 100)
      :error -> 0
    end
  end

  defp xml_order(items) do
    text = Enum.find(items, &(elem(&1, 0) == "text/xml"))
    app = Enum.find(items, &(elem(&1, 0) == "application/xml"))

    items =
      if text do
        q = max(elem(text, 1), if(app, do: elem(app, 1), else: 0))
        first = Enum.find_index(items, &(elem(&1, 0) in ~w(text/xml application/xml)))
        rest = Enum.reject(items, &(elem(&1, 0) in ~w(text/xml application/xml)))
        List.insert_at(rest, first, {"application/xml", q})
      else
        items
      end

    case Enum.find_index(items, &(elem(&1, 0) == "application/xml")) do
      nil ->
        items

      index ->
        xml = Enum.at(items, index)

        {result, _index} =
          Enum.reduce_while(index..(length(items) - 1), {items, index}, fn idx, {list, app_idx} ->
            {name, q} = Enum.at(list, idx)

            cond do
              q < elem(xml, 1) ->
                {:halt, {list, app_idx}}

              String.ends_with?(name, "+xml") ->
                swapped =
                  list
                  |> List.replace_at(app_idx, Enum.at(list, idx))
                  |> List.replace_at(idx, xml)

                {:cont, {swapped, idx}}

              true ->
                {:cont, {list, app_idx}}
            end
          end)

        result
    end
  end
end
