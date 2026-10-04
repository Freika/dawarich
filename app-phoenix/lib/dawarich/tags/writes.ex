defmodule Dawarich.Tags.Writes do
  @moduledoc false

  alias Dawarich.Tags.Validation

  @fields ~w(name icon color privacy_radius_meters)a
  @columns ~w(id user_id name icon color demo privacy_radius_meters created_at updated_at)a

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

  def update(repo, user, id, attrs, ctx) do
    transaction(repo, fn ->
      current = owned!(repo, user.id, id)

      case Validation.validate(repo, user, attrs, current, ctx.locale) do
        :rails ->
          repo.rollback(:rails)

        %{valid: false} = invalid ->
          render(repo, {:invalid, invalid}, ctx)

        %{valid: true} = valid ->
          tag = update_fields(repo, current, valid.tag, ctx)
          tag = adopt(repo, tag, ctx)
          render(repo, {:ok, %{tag: tag}}, ctx)
      end
    end)
  end

  def destroy(repo, user, id, ctx) do
    transaction(repo, fn ->
      tag = owned!(repo, user.id, id)
      repo.query!("DELETE FROM public.taggings WHERE tag_id=$1", [tag.id])
      repo.query!("DELETE FROM public.tags WHERE id=$1 AND user_id=$2", [tag.id, user.id])
      render(repo, {:ok, %{tag: tag}}, ctx)
    end)
  end

  defp owned!(repo, user_id, id) do
    case repo.query!(
           "SELECT #{Enum.join(@columns, ",")} FROM public.tags WHERE id=$1 AND user_id=$2 FOR UPDATE",
           [id, user_id]
         ).rows do
      [values] -> Map.new(Enum.zip(@columns, values))
      [] -> repo.rollback(:rails)
    end
  end

  defp update_fields(repo, current, tag, ctx) do
    if Map.take(current, @fields) == Map.take(tag, @fields) do
      tag
    else
      now = stamp(ctx.now)

      repo.query!(
        "UPDATE public.tags SET name=$2,icon=$3,color=$4,privacy_radius_meters=$5,updated_at=$6 WHERE id=$1",
        [tag.id, tag.name, tag.icon, tag.color, tag.privacy_radius_meters, now]
      )

      %{tag | updated_at: now}
    end
  end

  defp adopt(repo, %{demo: true} = tag, ctx) do
    now = stamp(Map.get(ctx, :adopt_now, ctx.now))
    repo.query!("UPDATE public.tags SET demo=false,updated_at=$2 WHERE id=$1", [tag.id, now])
    %{tag | demo: false, updated_at: now}
  end

  defp adopt(_repo, tag, _ctx), do: tag
  defp stamp(fun) when is_function(fun, 0), do: stamp(fun.())
  defp stamp(now), do: DateTime.to_naive(now)

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
