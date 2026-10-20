defmodule Dawarich.Test.AccountParity do
  @moduledoc false
  @keys ~w(account-current-key account-app-key account-owntracks-key account-overland-key)

  def normalize(html, key) do
    html
    |> String.replace(key, "CREDENTIAL")
    |> String.replace(~r/token=[A-Za-z0-9_.-]+/, "token=UPGRADE_TOKEN")
    |> LazyHTML.from_fragment()
    |> LazyHTML.to_tree()
    |> transform()
    |> Dawarich.Test.ParityHTML.normalize()
  end

  defp transform(nodes) when is_list(nodes), do: Enum.flat_map(nodes, &transform/1)

  defp transform({tag, attrs, children}) do
    map = Map.new(attrs)

    cond do
      tag == "code" and map["id"] in @keys ->
        value =
          if map["data-path"], do: map["data-path"] <> "?api_key=CREDENTIAL", else: "CREDENTIAL"

        [{tag, Enum.reject(attrs, fn {k, _} -> k in ~w(id data-path) end), [value]}]

      map["id"] == "account-key-qr" or (tag == "svg" and map["version"] == "1.1") ->
        [{"span", [], ["CREDENTIAL_QR"]}]

      tag == "input" and map["class"] == "hidden" ->
        []

      map["id"] == "import-checksum-progress" ->
        []

      tag == "form" and (map["id"] == "import-form" or map["data-controller"] == "upload") ->
        attrs =
          Enum.reject(attrs, fn {k, _} ->
            k in ~w(id action method accept-charset enctype data-upload-kind data-upload-name)
          end)

        children =
          Enum.reject(children, fn
            {"input", a, _} -> Map.new(a)["name"] == "authenticity_token"
            _ -> false
          end)

        children =
          transform(children)
          |> Enum.map(fn
            {"div", a, c} ->
              {"div", a,
               Enum.map(c, fn
                 {"input", x, []} ->
                   {"input", Enum.reject(x, fn {k, _} -> k == "disabled" end), []}

                 other ->
                   other
               end)}

            other ->
              other
          end)

        [{tag, attrs, children}]

      true ->
        attrs =
          if map["id"] == "native-rotate-api-key",
            do: List.keyreplace(attrs, "href", 0, {"href", "/settings/generate_api_key"}),
            else: attrs

        attrs =
          if map["id"] == "native-export-data",
            do: List.keyreplace(attrs, "href", 0, {"href", "/settings/users/export"}),
            else: attrs

        attrs =
          Enum.reject(attrs, fn {k, v} ->
            k in ~w(onclick onclose data-direct-upload-url) or
              (k == "id" and v in ~w(rotate-api-key export-data))
          end)

        attrs =
          if tag == "label" and map["for"] == "account-archive-selection",
            do: List.keyreplace(attrs, "for", 0, {"for", "archive"}),
            else: attrs

        attrs =
          if tag == "input" and map["id"] == "account-archive-selection",
            do: [
              {"type", "file"},
              {"id", "archive"},
              {"name", "archive"},
              {"accept", ".zip"},
              {"required", "required"},
              {"class", map["class"]}
            ],
            else: attrs

        [{tag, attrs, transform(children)}]
    end
  end

  defp transform(other), do: [other]
end
