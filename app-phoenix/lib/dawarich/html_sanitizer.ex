defmodule Dawarich.HtmlSanitizer do
  @moduledoc false
  import Kernel, except: [node: 1]

  @tags ~w(a abbr acronym address b big blockquote br cite code dd del dfn div dl dt em h1 h2 h3 h4 h5 h6 hr i img ins kbd li mark ol p pre samp small span strong sub sup time tt ul var)
  @attributes ~w(abbr alt cite class datetime height href lang name src title width xml:lang)
  @uri_attributes ~w(action cite href longdesc poster preload src xlink:href xml:base)
  @protocols ~w(afs aim callto data ed2k fax ftp gopher http https irc line mailto modem news nntp rsync rtsp sftp sms ssh tag tel telnet urn webcal xmpp)
  @data_mediatypes ~w(image/gif image/jpeg image/png text/css text/plain)
  @dropped_with_children ~w(svg math)
  @escaped %{"href" => nil, "action" => nil, "src" => nil, "name" => "a"}
  @control ~r/[`\x{0000}-\x{0020}\x{007f}\x{0080}-\x{0101}]/u
  @separator ~r/:|(&#0*58)|(&#x0*3a)|(%|&#37;)3A/i
  @scheme ~r/\A[a-z][a-z0-9+\-.]*(:|(&#0*58)|(&#x0*3a)|(%|&#37;)3A)/i
  @numeric ~r/&#(x[0-9a-f]+|[0-9]+);?/i
  @named %{"&apos;" => "'", "&quot;" => "\"", "&gt;" => ">", "&lt;" => "<", "&amp;" => "&"}
  @mediatype ~r/\A[a-z0-9!#$%&'*+\-.^_`|~]+\/[a-z0-9!#$%&'*+\-.^_`|~]+\z/

  def sanitize(""), do: ""

  def sanitize(html) when is_binary(html),
    do:
      html |> LazyHTML.from_fragment() |> LazyHTML.to_tree() |> scrub() |> LazyHTML.Tree.to_html()

  defp scrub(nodes), do: Enum.flat_map(nodes, &node/1)

  defp node(text) when is_binary(text), do: [text]
  defp node({:comment, _text}), do: []
  defp node({tag, _attrs, _children}) when tag in @dropped_with_children, do: []

  defp node({tag, attrs, children}) when tag in @tags,
    do: [{tag, attributes(tag, attrs), scrub(children)}]

  defp node({_tag, _attrs, children}), do: scrub(children)

  defp attributes(tag, attrs) do
    attrs
    |> Enum.filter(fn {name, _} -> name in @attributes end)
    |> Enum.reject(fn {name, value} -> name in @uri_attributes and not allowed_uri?(value) end)
    |> Enum.reject(fn {name, value} ->
      name == "src" and not Regex.match?(~r/[^[:space:]]/u, value)
    end)
    |> Enum.map(fn {name, value} -> {name, escape(tag, name, value)} end)
  end

  defp escape(tag, name, value) do
    case Map.fetch(@escaped, name) do
      {:ok, only} when only in [nil, tag] ->
        String.replace(value, ~r/[ "]/, fn
          " " -> "%20"
          "\"" -> "%22"
        end)

      _ ->
        value
    end
  end

  defp allowed_uri?(value) do
    uri =
      value
      |> String.replace(@control, "")
      |> unescape_html()
      |> decode_numeric()
      |> String.replace(@control, "")
      |> String.replace(~r/&(Tab|NewLine);/, "")
      |> String.replace("&colon;", ":")
      |> String.downcase()

    if Regex.match?(@scheme, uri) do
      [protocol | _] = String.split(uri, @separator, parts: 2)
      protocol in @protocols and (protocol != "data" or data_mediatype(uri) in @data_mediatypes)
    else
      true
    end
  end

  defp unescape_html(value) do
    Regex.replace(~r/&(?:apos|quot|gt|lt|amp);|&#(x[0-9a-f]+|\d+);/i, value, fn
      whole, "" -> Map.get(@named, whole, whole)
      whole, digits -> codepoint(whole, digits)
    end)
  end

  defp decode_numeric(value) do
    Regex.replace(@numeric, value, fn whole, digits ->
      {hex, digits} =
        if String.starts_with?(digits, ["x", "X"]),
          do: {true, String.slice(digits, 1..-1//1)},
          else: {false, digits}

      significant = String.replace(digits, ~r/\A0+/, "")

      if String.length(significant) > if(hex, do: 6, else: 7),
        do: whole,
        else: codepoint(whole, if(hex, do: "x" <> digits, else: digits))
    end)
  end

  defp codepoint(whole, "x" <> hex), do: to_char(whole, String.to_integer(hex, 16))
  defp codepoint(whole, "X" <> hex), do: to_char(whole, String.to_integer(hex, 16))
  defp codepoint(whole, decimal), do: to_char(whole, String.to_integer(decimal))

  defp to_char(_whole, code) when code in 0..0x10FFFF and code not in 0xD800..0xDFFF,
    do: <<code::utf8>>

  defp to_char(whole, _code), do: whole

  defp data_mediatype(uri) do
    case uri |> String.replace_prefix("data:", "") |> String.split(",", parts: 2) do
      [_only] ->
        nil

      [metadata, _data] ->
        mediatype =
          metadata
          |> String.replace_suffix(";base64", "")
          |> String.split(";", parts: 2)
          |> hd()
          |> String.trim()

        if Regex.match?(@mediatype, mediatype), do: mediatype, else: "text/plain"
    end
  end
end
