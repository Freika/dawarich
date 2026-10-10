defmodule Dawarich.Families.NativeCommandDispatch do
  @moduledoc false

  alias Dawarich.UserSettings

  alias Dawarich.Families.{
    WebCreate,
    WebUpdate,
    WebDestroy,
    WebInvitations,
    WebMemberships,
    Requests,
    SharingUpdate
  }

  def invoke(repo, user, :create, attrs, ctx, opts),
    do: WebCreate.run(repo, user, attrs, ctx, opts)

  def invoke(repo, user, :update, attrs, ctx, _), do: WebUpdate.run(repo, user, attrs, ctx)
  def invoke(repo, user, :delete, _, ctx, opts), do: WebDestroy.run(repo, user, ctx, opts)

  def invoke(repo, user, :invite, attrs, ctx, opts),
    do: WebInvitations.create(repo, user, attrs, ctx, opts)

  def invoke(repo, user, :accept_invitation, %{"token" => token}, ctx, opts)
      when is_binary(token),
      do: WebInvitations.accept(repo, user, token, ctx, Keyword.put(opts, :native_events, false))

  def invoke(repo, user, :remove_member, %{"id" => id}, ctx, _) when is_integer(id) and id > 0,
    do: WebMemberships.run(repo, user, id, ctx)

  def invoke(repo, user, :cancel_invitation, %{"id" => id}, ctx, _)
      when is_integer(id) and id > 0 do
    with %{role: 0} = family <- WebCreate.family(repo, user.id),
         [[token]] <-
           repo.query!(
             "SELECT token FROM family_invitations WHERE id=$1 AND family_id=$2",
             [id, family.id],
             log: false
           ).rows do
      WebInvitations.cancel(repo, user, token, ctx)
    else
      [] -> {:error, :not_found}
      _ -> {:error, :unauthorized}
    end
  end

  def invoke(repo, user, :set_sharing, attrs, ctx, _) do
    if valid_sharing?(attrs) do
      enabled = SharingUpdate.Web.boolean(attrs["enabled"])

      {:ok,
       SharingUpdate.web_write!(
         user.id,
         attrs |> Map.put("enabled", enabled) |> Map.put("web", true),
         ctx.now,
         repo
       )}
    else
      {:error, :invalid_input}
    end
  end

  def invoke(repo, user, :request_location, attrs, ctx, opts) do
    Requests.web_create(project(user), attrs, ctx.now, Keyword.put(opts, :repo, repo))
  end

  def invoke(
        repo,
        user,
        :respond_location,
        %{"id" => id, "decision" => decision} = attrs,
        ctx,
        opts
      )
      when is_integer(id) and id > 0 and decision in [:accept, :decline] do
    family = WebCreate.family(repo, user.id)

    case repo.query!(
           "SELECT target_user_id,status,expires_at FROM family_location_requests WHERE id=$1 AND family_id=$2 FOR UPDATE",
           [id, family.id],
           log: false
         ).rows do
      [] ->
        {:error, :not_found}

      [[target, _, _]] when target != user.id ->
        {:error, :unauthorized}

      [[_, status, expires]] ->
        now = Keyword.get(opts, :clock, fn -> ctx.now end).()

        if status == 0 and NaiveDateTime.compare(expires, DateTime.to_naive(now)) == :gt do
          Requests.web_respond(
            project(user),
            decision,
            Map.put(attrs, "id", Integer.to_string(id)),
            now,
            repo
          )
        else
          {:error, :expired}
        end
    end
  end

  def invoke(_, _, _, _, _, _), do: {:error, :invalid_input}

  defp valid_sharing?(attrs) do
    Map.has_key?(attrs, "enabled") and
      Enum.all?(attrs, fn {key, value} ->
        key in ~w(enabled duration share_history history_window history_before_sharing) and
          (is_binary(value) or is_boolean(value) or is_nil(value))
      end)
  end

  def result({:ok, status, {:object, fields}}) when status in [200, 201],
    do: {:ok, object(fields)}

  def result({:ok, status, {:object, fields}}),
    do: {:error, %{status: status, errors: Map.values(object(fields))}}

  def result({:ok, _} = result), do: result

  def result({:invalid, errors, name}),
    do: {:error, %{errors: errors, values: %{"name" => name}}}

  def result({:refused, reason}) when is_atom(reason), do: {:error, reason}
  def result({:refused, message}), do: {:error, %{errors: [message]}}

  def result({:error, reason}) when reason in [:not_authorized, :not_in_family],
    do: {:error, :unauthorized}

  def result({:error, reason})
      when reason in [:invite_failed, :accept_failed, :publication_failed],
      do: {:error, :unavailable}

  def result({:error, _} = result), do: result
  def result(_), do: {:error, :unavailable}

  defp object(fields),
    do:
      Map.new(fields, fn {key, val} ->
        {key, if(match?({:object, _}, val), do: object(elem(val, 1)), else: val)}
      end)

  defp project(user), do: Map.put(user, :timezone, UserSettings.get(user)["timezone"])
end
