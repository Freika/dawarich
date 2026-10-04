defmodule Dawarich.Tags.Writes do
  @moduledoc false

  alias Dawarich.Tags.Validation

  def create(repo, user, attrs, ctx) do
    transaction(repo, fn ->
      case Validation.validate(repo, user, attrs, %{}, ctx.locale) do
        :rails ->
          repo.rollback(:rails)

        %{valid: false} = invalid ->
          render(repo, {:invalid, invalid}, ctx)

        %{valid: true} = valid ->
          now = DateTime.to_naive(ctx.now)
          tag = Map.merge(valid.tag, %{user_id: user.id, created_at: now, updated_at: now})

          [[id]] =
            repo.query!(
              "INSERT INTO public.tags (user_id,name,icon,color,demo,privacy_radius_meters,created_at,updated_at) " <>
                "VALUES ($1,$2,$3,$4,false,$5,$6,$6) RETURNING id",
              [tag.user_id, tag.name, tag.icon, tag.color, tag.privacy_radius_meters, now]
            ).rows

          render(repo, {:ok, %{tag: Map.put(tag, :id, id)}}, ctx)
      end
    end)
  end

  defp render(repo, {status, result} = outcome, ctx) do
    case Map.get(ctx, :render) do
      nil ->
        outcome

      fun when is_function(fun, 1) ->
        case fun.(outcome) do
          {:ok, response} -> {status, Map.put(result, :response, response)}
          :rails -> repo.rollback(:rails)
        end
    end
  end

  defp transaction(repo, fun) do
    case repo.transaction(fun) do
      {:ok, outcome} -> outcome
      {:error, :rails} -> :rails
    end
  rescue
    _ in [Postgrex.Error, DBConnection.ConnectionError] -> :rails
  end
end
