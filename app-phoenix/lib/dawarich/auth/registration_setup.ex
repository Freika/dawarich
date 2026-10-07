defmodule Dawarich.Auth.RegistrationSetup do
  @moduledoc false
  alias Dawarich.Auth.{Account, RegistrationAttribution}
  alias Dawarich.{Notifications, Repo, SubscriptionToken}

  def ready?(%{self_hosted: false, registration_channel: :mobile} = context),
    do: is_function(get_in(context, [:callbacks, :webhook]), 1)

  def ready?(%{self_hosted: false} = context),
    do:
      is_function(get_in(context, [:callbacks, :webhook]), 1) and
        is_binary(System.get_env("JWT_SECRET_KEY")) and is_binary(System.get_env("MANAGER_URL"))

  def ready?(_), do: true

  def complete(user, params, session, context) do
    context = Dawarich.Auth.RegistrationCallbacks.context(context)
    repo = Map.get(context, :repo, Repo)

    if ready?(context) do
      case repo.transaction(fn -> finish(repo, user, params, session, context) end) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :signup_owner}
    end
  end

  defp finish(repo, user, params, session, context) do
    cloud = context[:self_hosted] == false

    if cloud do
      case Dawarich.Users.CreationEffects.apply(
             repo,
             user.id,
             Dawarich.Auth.RegistrationCallbacks.creation_options(context)
           ) do
        :ok -> :ok
        {:error, reason} -> repo.rollback(reason)
      end
    end

    session =
      if cloud,
        do: RegistrationAttribution.apply(repo, user, params, session, context),
        else: session

    invitation = context[:invitation]
    accepted = if invitation, do: accept(repo, user, invitation, context), else: false
    session = claim(repo, user, session, context)

    if cloud and not accepted and context[:registration_channel] != :mobile do
      user = repo.update!(Ecto.Changeset.change(user, %{status: 3}), log: false)
      {linker, session} = Map.pop(session, "gads_linker")

      token =
        SubscriptionToken.generate(user, DateTime.utc_now(), Ecto.UUID.generate(),
          variant: "reverse_trial"
        )

      url = System.get_env("MANAGER_URL") <> "/checkout?token=" <> token

      url =
        if is_binary(linker) and linker != "",
          do: url <> "&_gl=" <> URI.encode(linker, &URI.char_unreserved?/1),
          else: url

      %{
        user: user,
        session: Map.drop(session, ~w(warden.user.user.key)),
        location: url,
        signed_in: false
      }
    else
      %{
        user: repo.get!(Account, user.id, log: false),
        session: session,
        location: if(invitation, do: "/family", else: "/"),
        signed_in: true
      }
    end
  end

  defp claim(repo, user, session, context) do
    case Map.pop(session, "pending_import_ticket") do
      {nil, session} ->
        session

      {ticket, session} ->
        user = %{user | settings: Dawarich.Accounts.settings(user.id)}

        Dawarich.PendingImports.Claim.claim(repo, user, ticket, %{
          now: Map.get(context, :clock, &DateTime.utc_now/0).()
        })

        session
    end
  end

  defp accept(repo, user, invitation, context) do
    if invitation.acceptable and Account.normalize_email(invitation.email) == user.email do
      if context[:self_hosted] == false do
        callback = get_in(context, [:callbacks, :accept_invitation])

        if is_function(callback, 2),
          do:
            if(callback.(user.id, invitation.id) == :ok,
              do: true,
              else: repo.rollback(:family_owner)
            ),
          else: repo.rollback(:family_owner)
      else
        self_hosted_invitation(repo, user, invitation, context)
      end
    else
      false
    end
  end

  defp self_hosted_invitation(repo, user, invitation, context) do
    now = Map.get(context, :clock, &DateTime.utc_now/0).() |> DateTime.to_naive()

    repo.query!("SELECT id FROM families WHERE id=$1 FOR UPDATE", [invitation.family_id],
      log: false
    )

    case repo.query!(
           "SELECT status,expires_at FROM family_invitations WHERE id=$1 FOR UPDATE",
           [invitation.id],
           log: false
         ).rows do
      [[0, expires]] ->
        if NaiveDateTime.compare(expires, now) != :lt and
             repo.query!("SELECT 1 FROM family_memberships WHERE user_id=$1", [user.id],
               log: false
             ).rows == [] do
          repo.query!(
            "INSERT INTO family_memberships(user_id,family_id,role,created_at,updated_at) VALUES($1,$2,1,$3,$3)",
            [user.id, invitation.family_id, now],
            log: false
          )

          repo.query!(
            "UPDATE family_invitations SET status=1,updated_at=$2 WHERE id=$1",
            [invitation.id, now],
            log: false
          )

          locale = Map.get(context, :locale, "en")

          title =
            DawarichWeb.Translate.t(
              locale,
              "services.families.accept_invitation.welcome_to_family",
              %{}
            )

          body =
            DawarichWeb.Translate.t(
              locale,
              "services.families.accept_invitation.you_ve_joined_the_family_name",
              %{"name" => invitation.name}
            )

          Notifications.create!(repo, user.id, :info, title, body, now)

          [[owner, settings]] =
            repo.query!(
              "SELECT u.id,u.settings FROM users u JOIN families f ON f.creator_id=u.id WHERE f.id=$1",
              [invitation.family_id],
              log: false
            ).rows

          owner_locale = Dawarich.UserSettings.safe(settings)["locale"] || "en"

          title =
            DawarichWeb.Translate.t(
              owner_locale,
              "services.families.accept_invitation.new_family_member",
              %{}
            )

          body =
            DawarichWeb.Translate.t(
              owner_locale,
              "services.families.accept_invitation.email_has_joined_your_family",
              %{"email" => user.email}
            )

          Notifications.create!(repo, owner, :info, title, body, now)
          true
        else
          false
        end

      _ ->
        false
    end
  end
end
