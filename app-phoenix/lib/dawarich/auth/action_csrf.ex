defmodule Dawarich.Auth.ActionCsrf do
  @moduledoc false
  alias DawarichWeb.RailsCsrf

  def valid?(session, token, method, path)
      when is_binary(token) and is_binary(method) and is_binary(path) do
    RailsCsrf.valid?(session, token, URI.parse(path).path, method)
  rescue
    ArgumentError -> false
  end

  def valid?(_, _, _, _), do: false
end
