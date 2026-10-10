defmodule Dawarich.Admin.Users do
  @moduledoc false
  require Logger

  alias Dawarich.Accounts.User

  alias Dawarich.Admin.{
    Access,
    SettingWrites,
    UserCreate,
    UserRoles,
    UserSecurity,
    UserUpdate,
    UsersPage
  }

  alias Dawarich.Auth.AccountDestroy
  alias Dawarich.Repo

  def list(scope, query) do
    with {:ok, scope} <- Access.admit(scope, :admin, env: env()) do
      UsersPage.list(scope.user, query)
    end
  rescue
    error -> failed(error, :unavailable)
  end

  def get(scope, id, kind) do
    with {:ok, scope} <- Access.admit(scope, :admin, env: env()),
         {:ok, target} <- UsersPage.find(scope.user, target_id(id), kind) do
      if kind == :show do
        {:ok,
         %{
           user: struct(User, Map.take(target, [:id, :email, :admin, :status, :api_key])),
           details: Map.drop(target, [:api_key, :counts]),
           counts: target.counts
         }}
      else
        {:ok, target}
      end
    end
  rescue
    error -> failed(error, :unavailable)
  end

  def create(scope, params),
    do:
      write(scope, fn actor, context ->
        with :ok <- input(params), do: UserCreate.call(actor, params, context)
      end)

  def update(scope, id, params),
    do:
      write(
        scope,
        fn actor, context ->
          with :ok <- input(params), do: UserUpdate.call(actor, target_id(id), params, context)
        end,
        role_write?(params)
      )

  def delete(scope, id),
    do:
      write(
        scope,
        fn actor, context ->
          id = target_id(id)

          cond do
            id == actor.id -> {:error, :self}
            is_nil(id) or id <= 0 -> {:error, :not_found}
            true -> delete_target(actor, id, context)
          end
        end,
        true
      )

  def update_registration(scope, params),
    do:
      write(scope, fn actor, context ->
        with :ok <- input(params), do: SettingWrites.registration(actor, params, context)
      end)

  def rotate_api_key(scope, id),
    do:
      write(scope, fn actor, context ->
        UserSecurity.rotate(actor, target_id(id), context)
      end)

  def send_password_reset(scope, id),
    do:
      write(scope, fn actor, context ->
        UserSecurity.reset(actor, target_id(id), context)
      end)

  defp write(scope, effect, lock_admins \\ false) do
    with {:ok, _} <- Access.admit(scope, :admin, write: true, env: env()) do
      context = context(scope)
      repo = context.repo

      case repo.transaction(fn ->
             with :ok <- maybe_lock(repo, lock_admins),
                  {:ok, fresh} <- Access.admit(scope, :admin, write: true, env: context.env) do
               case normalize(effect.(fresh.user, context)) do
                 {:error, reason} -> repo.rollback(reason)
                 result -> result
               end
             else
               {:error, reason} -> repo.rollback(reason)
             end
           end) do
        {:ok, result} -> result
        {:error, reason} -> {:error, reason}
      end
    end
  rescue
    error in Postgrex.Error ->
      if error.postgres[:code] in [:lock_not_available, :deadlock_detected],
        do: {:error, :unauthorized},
        else: {:error, :unavailable}

    error ->
      failed(error, :unavailable)
  end

  defp delete_target(actor, id, context) do
    repo = context.repo

    case repo.query!("SELECT admin FROM users WHERE id=$1 AND deleted_at IS NULL", [id],
           log: false
         ).rows do
      [] ->
        {:error, :not_found}

      [[admin]] ->
        [[count]] =
          repo.query!("SELECT count(*) FROM users WHERE admin AND deleted_at IS NULL", [],
            log: false
          ).rows

        if admin == true and count == 1 do
          {:error, :last_admin}
        else
          AccountDestroy.request_as_admin(actor.id, id, AccountDestroy.context(context))
        end
    end
  end

  defp maybe_lock(repo, true), do: UserRoles.lock(repo)
  defp maybe_lock(_repo, false), do: :ok

  defp role_write?(params) when is_map(params),
    do: Map.has_key?(params, "admin") or Map.has_key?(params, "status")

  defp role_write?(_), do: false

  defp input(params) when is_map(params) do
    valid =
      Enum.all?(Map.take(params, ~w(email password)), fn {_, value} ->
        is_nil(value) or is_binary(value)
      end) and
        Enum.all?(Map.take(params, ~w(admin status registration_enabled)), fn {_, value} ->
          is_nil(value) or is_binary(value) or is_boolean(value) or is_integer(value)
        end)

    if valid, do: :ok, else: {:error, :invalid_input}
  end

  defp input(_), do: {:error, :invalid_input}

  defp context(scope) do
    env = env()

    Application.get_env(:dawarich, __MODULE__, %{})
    |> Map.merge(%{
      repo: repo(),
      env: env,
      locale: scope.locale,
      self_hosted: Dawarich.ReleaseMigration.self_hosted?(env),
      oidc: Dawarich.Auth.Admission.oidc?(env)
    })
  end

  defp env, do: Map.get(Application.get_env(:dawarich, __MODULE__, %{}), :env, System.get_env())
  defp repo, do: Map.get(Application.get_env(:dawarich, __MODULE__, %{}), :repo, Repo)

  defp normalize({:ok, _} = result), do: result
  defp normalize({:error, :actor}), do: {:error, :not_found}

  defp normalize({:error, reason})
       when reason in [
              :self,
              :last_admin,
              :cannot_delete_account,
              :unauthorized,
              :stale_session,
              :invalid_input,
              :not_found
            ],
       do: {:error, reason}

  defp normalize({:invalid, message}), do: {:error, {:validation, message}}
  defp normalize({:blocked, message}), do: {:error, {:blocked, message}}
  defp normalize({:handoff, :actor}), do: {:error, :unauthorized}
  defp normalize({:handoff, :target}), do: {:error, :not_found}

  defp normalize({:handoff, reason}) when reason in [:oidc, :cloud, :encryption],
    do: {:error, reason}

  defp normalize({:handoff, :invalid_status}), do: {:error, :invalid_input}
  defp normalize(_), do: {:error, :unavailable}

  defp target_id(id) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807, do: id

  defp target_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {number, ""} -> target_id(number)
      _ -> nil
    end
  end

  defp target_id(_), do: nil

  defp failed(error, reason) do
    Logger.warning("admin users call failed: " <> inspect(error.__struct__))
    {:error, reason}
  end
end
