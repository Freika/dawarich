defmodule Dawarich.MapMatching.Atlas.Endpoint do
  alias Dawarich.Imports.Trek.Endpoint, as: TrekEndpoint
  alias Dawarich.MapMatching.Atlas.Client.Error

  def resolve!(url, path \\ "") do
    uri = validate!(url)
    {uri, address} = TrekEndpoint.resolve!(URI.to_string(uri), self_hosted?: true)
    {%{uri | path: (uri.path || "") <> path}, address}
  rescue
    _ -> raise Error, code: "invalid_url", message: "Atlas URL was rejected"
  end

  defp validate!(url) when is_binary(url) do
    uri = url |> String.trim() |> String.trim_trailing("/") |> URI.parse()

    if uri.scheme not in ["http", "https"] or uri.host in [nil, ""] or
         uri.userinfo != nil or uri.query != nil or uri.fragment != nil or
         uri.port not in 1..65_535 do
      raise Error, code: "invalid_url", message: "Atlas URL was rejected"
    end

    uri
  end

  defp validate!(_), do: raise(Error, code: "invalid_url", message: "Atlas URL was rejected")
end
