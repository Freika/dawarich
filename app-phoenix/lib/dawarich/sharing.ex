defmodule Dawarich.Sharing do
  @moduledoc false
  alias Dawarich.Sharing.{Commands, Resources}

  def page(scope, resource, params \\ %{}, opts \\ []) do
    with {:ok, user, ctx} <- Dawarich.Families.NativeReads.actor(scope, opts),
         :ok <- Resources.admit(resource, user.id),
         :ok <- Resources.access(user, resource, ctx),
         {:ok, page} <- Resources.read(user, resource, params, ctx, scope.locale) do
      {:ok, Resources.sanitize(page)}
    end
  rescue
    _ -> {:error, :invalid_input}
  end

  def change(scope, resource, action, attrs, opts \\ []),
    do: Commands.run(scope, resource, action, attrs, opts)

  def generate_phrase(scope, opts \\ []) do
    with {:ok, _, _} <- Dawarich.Families.NativeReads.actor(scope, opts),
         do: {:ok, Dawarich.ShareManagement.Read.phrase()}
  end

  def reveal(scope, resource, field, opts \\ []) do
    with {:ok, user, ctx} <- Dawarich.Families.NativeReads.actor(scope, opts),
         :ok <- Resources.admit(resource, user.id),
         true <- resource.type == :shared and field in [:phrase, :url],
         {:ok, %{share: share}} <- Resources.read(user, resource, %{}, ctx, scope.locale) do
      {:ok, if(field == :phrase, do: share.magic_phrase || "", else: "/s/" <> share.id)}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_input}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def subscribe(scope, opts \\ []) do
    with {:ok, user, _} <- Dawarich.Families.NativeReads.actor(scope, opts),
         do: Phoenix.PubSub.subscribe(Dawarich.PubSub, "sharing:user:#{user.id}")
  end

  def version(id) do
    if Dawarich.SharedLinks.canonical?(id) do
      case Dawarich.Repo.query!(
             "SELECT user_id,resource_type,resource_id,magic_phrase,settings,expires_at,revoked_at,updated_at FROM shared_links WHERE id=$1::text::uuid",
             [id],
             log: false
           ).rows do
        [row] ->
          :crypto.hash(:sha256, :erlang.term_to_binary(row)) |> Base.url_encode64(padding: false)

        [] ->
          nil
      end
    end
  rescue
    _ -> nil
  end
end
