defmodule Dawarich.Families.WebInvitations do
  @moduledoc false
  alias Dawarich.{Entitlements, Notifications, I18n}
  alias Dawarich.Families.{WebCreate, MemberSync}
  alias Dawarich.Jobs.Ownership

  def create(repo, user, attrs, ctx, opts \\ []) do
    case WebCreate.family(repo, user.id) do
      nil -> {:error, :not_in_family}
      %{role: role} when role != 0 -> {:error, :not_authorized}
      family -> invite(repo, user, family, attrs["email"], ctx, opts)
    end
  end

  def cancel(repo, user, token, ctx) do
    case WebCreate.family(repo, user.id) do
      nil ->
        {:error, :not_in_family}

      %{role: role} when role != 0 ->
        {:error, :not_authorized}

      family ->
        case repo.query!(
               "UPDATE family_invitations SET status=3,updated_at=$1 WHERE token=$2 AND family_id=$3 RETURNING id",
               [DateTime.to_naive(ctx.now), token, family.id],
               log: false
             ).rows do
          [[id]] -> {:ok, id}
          [] -> {:error, :not_found}
        end
    end
  end

  def accept(repo, user, token, ctx, opts \\ []) do
    result =
      repo.transaction(fn ->
        case repo.query!(
               "SELECT id,family_id,email,status,expires_at FROM family_invitations WHERE token=$1 FOR UPDATE",
               [token],
               log: false
             ).rows do
          [] ->
            repo.rollback(:not_found)

          [[id, family, email, status, expires]] ->
            cond do
              NaiveDateTime.compare(expires, DateTime.to_naive(ctx.now)) == :lt ->
                repo.rollback(:invitation_expired)

              status != 0 ->
                repo.rollback(:invitation_processed)

              email != user.email ->
                repo.rollback(:invitation_email_mismatch)

              WebCreate.family(repo, user.id) != nil ->
                repo.rollback(:already_in_family)

              true ->
                join(repo, user, id, family, ctx, opts)
            end
        end
      end)

    case result do
      {:ok, {:error, reason}} -> {:error, reason}
      other -> other
    end
  rescue
    _error -> {:error, :accept_failed}
  end

  defp invite(repo, user, family, email, ctx, opts) when is_binary(email) do
    email = email |> String.downcase() |> String.trim()

    cond do
      email == "" ->
        {:refused,
         Dawarich.WebValidation.message(
           ctx.locale,
           "family/invitation",
           "email",
           "errors.messages.blank"
         )}

      not Regex.match?(
        ~r/\A[a-zA-Z0-9.!\#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\z/,
        email
      ) ->
        {:refused,
         Dawarich.WebValidation.message(
           ctx.locale,
           "family/invitation",
           "email",
           "errors.messages.invalid"
         )}

      not ctx.self_hosted and capacity(repo, family.id, ctx.now) >= 5 ->
        {:refused,
         Dawarich.WebValidation.message(
           ctx.locale,
           "family",
           "family",
           "services.families.invite.family_full"
         )}

      exists?(
        repo,
        "SELECT 1 FROM users u JOIN family_memberships m ON m.user_id=u.id WHERE u.email=$1",
        [email]
      ) ->
        {:refused,
         Dawarich.WebValidation.message(
           ctx.locale,
           "family/invitation",
           "email",
           "services.families.invite.user_already_in_family"
         )}

      exists?(
        repo,
        "SELECT 1 FROM family_invitations WHERE family_id=$1 AND email=$2 AND status=0 AND expires_at>$3",
        [family.id, email, DateTime.to_naive(ctx.now)]
      ) ->
        {:refused,
         Dawarich.WebValidation.message(
           ctx.locale,
           "family/invitation",
           "email",
           "services.families.invite.invitation_already_sent"
         )}

      true ->
        persist(repo, user, family, email, ctx, opts)
    end
  end

  defp invite(_repo, _user, _family, _email, _ctx, _opts), do: {:error, :invalid_shape}

  defp persist(repo, user, family, email, ctx, opts) do
    repo.transaction(fn ->
      if Ownership.lock(repo, "command:mail.family_invitation") != :oban,
        do: repo.rollback(:mail_source_owned)

      at = DateTime.to_naive(ctx.now)
      token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

      [[id]] =
        repo.query!(
          "INSERT INTO family_invitations(family_id,email,token,status,invited_by_id,expires_at,created_at,updated_at) VALUES($1,$2,$3,0,$4,$5,$6,$6) RETURNING id",
          [family.id, email, token, user.id, NaiveDateTime.add(at, 7, :day), at],
          log: false
        ).rows

      payload = %{"invitation_id" => id, "locale" => ctx.locale}
      Keyword.get(opts, :enqueue, &enqueue/3).(repo, payload, ctx.now)
      key = if ctx.self_hosted, do: "sent_self_hosted", else: "sent"

      WebCreate.notify(fn ->
        Keyword.get(opts, :notify, fn ->
          Notifications.create!(
            repo,
            user.id,
            :info,
            t(
              Dawarich.Mail.ExploreFeatures.locale(user.settings, "en"),
              "invite",
              "invitation_sent"
            ),
            t(Dawarich.Mail.ExploreFeatures.locale(user.settings, "en"), "invite", key, %{
              "email" => email
            }),
            at
          )
        end).()
      end)

      id
    end)
  rescue
    _error -> {:error, :invite_failed}
  end

  defp enqueue(repo, payload, now) do
    id = payload["invitation_id"]

    repo.query!(
      "INSERT INTO job_outbox(event_id,command_type,command_version,payload,aggregate_id,dedupe_key,scheduled_at,metadata) VALUES($1,'mail.family_invitation',1,$2,$3,$4,$5,$6)",
      [
        Ecto.UUID.dump!(Ecto.UUID.generate()),
        payload,
        id,
        "family-invitation:#{id}",
        now,
        %{"producer" => "Families::Invite"}
      ],
      log: false
    )
  end

  defp join(repo, user, invitation, family, ctx, opts) do
    [[creator, name, access]] =
      repo.query!(
        "SELECT creator_id,name,access_until FROM families WHERE id=$1 FOR UPDATE",
        [family],
        log: false
      ).rows

    [[plan, until]] =
      repo.query!("SELECT plan,active_until FROM users WHERE id=$1 FOR UPDATE", [creator],
        log: false
      ).rows

    access = WebCreate.refresh_access(repo, family, access, plan, until, ctx.self_hosted)

    cond do
      not ctx.self_hosted and not Entitlements.inherited?(access, plan, until, ctx.now) ->
        {:error, :family_lapsed}

      not ctx.self_hosted and capacity(repo, family, ctx.now) > 5 ->
        {:error, :family_full}

      true ->
        join_member(repo, user, invitation, family, creator, name, ctx, opts)
    end
  end

  defp join_member(repo, user, invitation, family, creator, name, ctx, opts) do
    at = DateTime.to_naive(ctx.now)

    repo.query!(
      "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES($1,$2,1,$3,$3)",
      [family, user.id, at],
      log: false
    )

    if not ctx.self_hosted, do: MemberSync.run(repo, family, now: ctx.now)

    repo.query!(
      "UPDATE family_invitations SET status=1,updated_at=$1 WHERE id=$2",
      [at, invitation],
      log: false
    )

    Keyword.get(opts, :settled, fn -> :ok end).()
    locale = Dawarich.Mail.ExploreFeatures.locale(user.settings, "en")

    Notifications.create!(
      repo,
      user.id,
      :info,
      t(locale, "accept_invitation", "welcome_to_family"),
      t(locale, "accept_invitation", "you_ve_joined_the_family_name", %{"name" => name}),
      at
    )

    [[settings]] =
      repo.query!("SELECT settings FROM users WHERE id=$1", [creator], log: false).rows

    locale = Dawarich.Mail.ExploreFeatures.locale(settings, "en")

    Notifications.create!(
      repo,
      creator,
      :info,
      t(locale, "accept_invitation", "new_family_member"),
      t(locale, "accept_invitation", "email_has_joined_your_family", %{"email" => user.email}),
      at
    )

    family
  end

  defp capacity(repo, family, now) do
    [[count]] =
      repo.query!(
        "SELECT (SELECT count(*) FROM family_memberships WHERE family_id=$1)+(SELECT count(*) FROM family_invitations WHERE family_id=$1 AND status=0 AND expires_at>$2)",
        [family, DateTime.to_naive(now)],
        log: false
      ).rows

    count
  end

  defp exists?(repo, sql, args), do: repo.query!(sql, args, log: false).rows != []

  defp t(locale, service, key, args \\ %{}) do
    {:ok, message} = I18n.t(locale, "services.families." <> service <> "." <> key, args)
    message
  end
end
