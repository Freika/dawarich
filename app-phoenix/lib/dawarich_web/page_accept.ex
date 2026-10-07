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

  @browser_like ~r/,\s*\*\/\*|\*\/\*\s*,/
  @separator ~r/;\s*q="?/
  @header ~r/[^,\s"](?:[^,"]|"[^"]*")*/
  @mime ~r/\A(?:\*\/\*|[a-zA-Z0-9][a-zA-Z0-9!\#$&\-^_.+]{0,126}\/(?:\*|[a-zA-Z0-9][a-zA-Z0-9!\#$&\-^_.+]{0,126}))\z/
  @number ~r/\A[\t\n\v\f\r ]*([+-]?(?:[0-9](?:_?[0-9])*(?:\.(?:[0-9](?:_?[0-9])*)?)?|\.[0-9](?:_?[0-9])*)(?:[eE][+-]?[0-9](?:_?[0-9])*)?)/

  def formats(accept, xhr?) do
    accept = String.trim(accept)

    cond do
      accept == "" -> [if(xhr?, do: "text/javascript", else: "text/html")]
      not xhr? and Regex.match?(@browser_like, accept) -> ["text/html"]
      true -> parse(accept)
    end
  end

  def negotiate(formats, available) do
    Enum.find_value(formats, fn type ->
      cond do
        type == "*/*" -> List.first(available)
        type in available -> type
        true -> nil
      end
    end)
  end

  defp parse(accept) do
    names =
      if String.contains?(accept, ",") do
        Regex.scan(@header, accept)
        |> Enum.flat_map(fn [header] ->
          [name | rest] = Regex.split(@separator, header)
          name = String.trim(name)

          q_text =
            rest
            |> Enum.reverse()
            |> Enum.drop_while(&(&1 == ""))
            |> Enum.reverse()
            |> List.first()

          q = quality(q_text, name)
          for type <- expand(name), do: {type, q}
        end)
        |> Enum.with_index()
        |> Enum.sort_by(fn {{_type, q}, index} -> {-q, index} end)
        |> Enum.map(fn {item, _index} -> item end)
        |> xml_order()
        |> Enum.map(&elem(&1, 0))
      else
        name = Regex.split(@separator, accept) |> hd()
        name = if Regex.match?(@separator, accept), do: String.trim(name), else: name
        expand(name)
      end

    types = Enum.map(names, &canonical/1)

    if :invalid_type in types,
      do: :invalid_type,
      else: types |> Enum.uniq() |> Enum.filter(&(&1 in @types or &1 == "*/*"))
  end

  defp expand(""), do: []

  defp expand(name) do
    case Regex.run(~r/^(text|application)\/\*/, name) do
      [_, family] ->
        Enum.filter(@types, fn type ->
          String.contains?(type, family) or
            Enum.any?(@aliases, fn {other, target} ->
              target == type and String.contains?(other, family)
            end)
        end)

      _ ->
        [name]
    end
  end

  defp canonical(name) do
    type = name |> String.split(";", parts: 2) |> hd() |> String.trim_trailing()

    if Regex.match?(@mime, type),
      do: Map.get(@aliases, type, type),
      else: :invalid_type
  end

  defp quality(nil, "*/*"), do: 0
  defp quality(nil, _name), do: 100

  defp quality(text, _name) do
    case Regex.run(@number, text) do
      [_, number] ->
        number = String.replace(number, "_", "")
        number = Regex.replace(~r/\A([+-]?)\./, number, "\\g{1}0.")
        {value, _} = Float.parse(number)
        trunc(value * 100)

      _ ->
        0
    end
  end

  defp xml_order(items) do
    text_idx = Enum.find_index(items, &(elem(&1, 0) == "text/xml"))
    app_idx = Enum.find_index(items, &(elem(&1, 0) == "application/xml"))

    {items, app_idx} =
      cond do
        text_idx != nil and app_idx != nil ->
          app = Enum.at(items, app_idx)
          text = Enum.at(items, text_idx)
          app = {elem(app, 0), max(elem(app, 1), elem(text, 1))}
          items = List.replace_at(items, app_idx, app)

          if app_idx > text_idx do
            items = items |> List.replace_at(app_idx, text) |> List.replace_at(text_idx, app)
            {List.delete_at(items, app_idx), text_idx}
          else
            {List.delete_at(items, text_idx), app_idx}
          end

        text_idx != nil ->
          {List.replace_at(
             items,
             text_idx,
             {"application/xml", elem(Enum.at(items, text_idx), 1)}
           ), nil}

        true ->
          {items, app_idx}
      end

    if app_idx == nil do
      items
    else
      xml = Enum.at(items, app_idx)

      {result, _} =
        Enum.reduce_while(app_idx..(length(items) - 1), {items, app_idx}, fn idx,
                                                                             {list, current} ->
          {name, q} = Enum.at(list, idx)

          cond do
            q < elem(xml, 1) ->
              {:halt, {list, current}}

            String.ends_with?(name, "+xml") ->
              swapped =
                list |> List.replace_at(current, Enum.at(list, idx)) |> List.replace_at(idx, xml)

              {:cont, {swapped, idx}}

            true ->
              {:cont, {list, current}}
          end
        end)

      result
    end
  end
end
