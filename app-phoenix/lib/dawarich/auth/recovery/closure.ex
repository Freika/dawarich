defmodule Dawarich.Auth.Recovery.Closure do
  @moduledoc false
  import Ecto.Query
  alias Dawarich.Auth.{Account, SecurityNotifications, SessionCookie, Trackable}
  alias Dawarich.Auth.Recovery.{Flow, Settings, Token}
  alias Dawarich.{RailsSecret, Repo}

  def dispatch(method, "/users/password", params, session, context)
      when method in ["PUT", "PATCH"] do
    case reset(params, context) do
      {:ok, user} ->
        {next, cookie} =
          SessionCookie.for_login(
            session,
            user,
            text(context, "devise.passwords.updated"),
            secret(context)
          )

        {:ok, %{status: 303, location: "/", session: next, cookie: cookie}}

      {:error, :notification_owner} ->
        {:error, :notification_owner}

      {:error, error} ->
        {:ok,
         %{
           status: 422,
           location: nil,
           session: session,
           view: :password_edit,
           assigns: %{error: error, token: params["user[reset_password_token]"]}
         }}

      other ->
        other
    end
  end

  def dispatch(method, path, params, session, context) do
    Flow.dispatch(
      method,
      path,
      params,
      session,
      Map.merge(context, %{enabled: true, self_hosted: true, oidc: false, headers: []})
    )
  end

  def reset(params, context) do
    repo = Map.get(context, :repo, Repo)
    raw = params["user[reset_password_token]"]
    digest = Token.digest(:reset_password_token, raw, secret(context))
    now = Map.get(context, :clock, &DateTime.utc_now/0).()

    result =
      repo.transaction(fn ->
        user =
          if is_binary(digest),
            do:
              repo.one(
                from(u in Account,
                  where: u.reset_password_token == ^digest and is_nil(u.deleted_at),
                  lock: "FOR UPDATE"
                ),
                log: false
              )

        cond do
          is_nil(user) -> {:error, Token.token_error(raw)}
          expired?(user.reset_password_sent_at, now) -> {:error, :expired}
          true -> save(repo, user, params, now, context)
        end
      end)

    case result do
      {:ok, value} -> value
      {:error, reason} -> {:error, reason}
    end
  end

  defp expired?(nil, _), do: true
  defp expired?(sent, now), do: DateTime.compare(sent, DateTime.add(now, -21_600)) == :lt

  defp save(repo, user, params, now, context) do
    password = params["user[password]"]
    confirmation = params["user[password_confirmation]"]
    errors = password_errors(password, confirmation)

    if errors != [] do
      {:error, {:validation, errors}}
    else
      [[settings]] =
        repo.query!("SELECT settings FROM users WHERE id=$1", [user.id], log: false).rows

      case Settings.sanitize(settings) do
        {:ok, settings} ->
          hash =
            Bcrypt.hash_pwd_salt(binary_part(password, 0, min(byte_size(password), 72)),
              log_rounds: Map.get(context, :log_rounds, 12)
            )

          changes = %{
            encrypted_password: hash,
            reset_password_token: nil,
            reset_password_sent_at: nil,
            failed_attempts: 0,
            locked_at: nil,
            unlock_token: nil,
            failed_otp_attempts: 0,
            otp_locked_at: nil,
            settings: settings,
            updated_at: now
          }

          changes =
            if context[:sign_in_ip],
              do: Map.merge(changes, Trackable.changes(user, now, context.sign_in_ip)),
              else: changes

          if not SecurityNotifications.ready?(context, changes),
            do: repo.rollback(:notification_owner)

          updated = repo.update!(Ecto.Changeset.change(user, changes), log: false)
          SecurityNotifications.enqueue(repo, user, updated, changes, context)
          {:ok, updated}

        :error ->
          {:handoff, :settings_callback}
      end
    end
  end

  defp password_errors(password, confirmation) do
    if Token.blank?(password) do
      [:blank]
    else
      length = length(String.codepoints(password))

      for {kind, failed} <- [
            confirmation: confirmation != nil and confirmation != password,
            too_short: length < 12,
            too_long: length > 128
          ],
          failed,
          do: kind
    end
  end

  defp secret(context), do: Map.get_lazy(context, :secret, &RailsSecret.fetch/0)
  defp text(context, key), do: DawarichWeb.Translate.t(Map.get(context, :locale, "en"), key, %{})
end
