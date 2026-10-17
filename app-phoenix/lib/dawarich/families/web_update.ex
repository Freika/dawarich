defmodule Dawarich.Families.WebUpdate do
  @moduledoc false
  alias Dawarich.Families.WebCreate

  def run(repo, user, attrs, ctx) do
    case WebCreate.family(repo, user.id) do
      nil -> {:error, :not_in_family}
      %{role: role} when role != 0 -> {:error, :not_authorized}
      family -> update(repo, family, attrs, ctx)
    end
  end

  defp update(repo, family, attrs, ctx) do
    name = attrs["name"]

    cond do
      not Map.has_key?(attrs, "name") or is_map(name) or is_list(name) ->
        {:ok, family.id}

      not is_binary(name) and not is_nil(name) ->
        {:error, :invalid_shape}

      true ->
        case validate(name, ctx.locale) do
          [] ->
            repo.query!(
              "UPDATE families SET name=$1,updated_at=$2 WHERE id=$3",
              [name, DateTime.to_naive(ctx.now), family.id],
              log: false
            )

            {:ok, family.id}

          errors ->
            {:invalid, errors, name}
        end
    end
  end

  defp validate(name, locale) do
    cond do
      is_nil(name) or String.trim(name) == "" ->
        [Dawarich.WebValidation.message(locale, "family", "name", "errors.messages.blank")]

      length(String.codepoints(name)) > 50 ->
        [
          Dawarich.WebValidation.message(locale, "family", "name", "errors.messages.too_long", %{
            "count" => 50
          })
        ]

      true ->
        []
    end
  end
end
