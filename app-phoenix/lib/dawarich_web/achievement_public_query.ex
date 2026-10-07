defmodule DawarichWeb.AchievementPublicQuery do
  @moduledoc false
  alias Dawarich.Auth.Admission
  alias DawarichWeb.Api.SourceParams

  def decode(raw, fields) do
    with true <- byte_size(raw) <= 65_536,
         {:ok, _} <- SourceParams.decode(raw) do
      query =
        raw
        |> String.split("&", trim: true)
        |> Enum.filter(fn pair ->
          key = pair |> String.split("=", parts: 2) |> hd() |> URI.decode_www_form()
          Enum.any?(fields, &(key == &1 or String.starts_with?(key, &1 <> "[")))
        end)
        |> Enum.join("&")

      Admission.form(query, "", fields)
    else
      _ -> {:handoff, :parameters}
    end
  end
end
