defmodule Dawarich.Auth.Recovery.Mail do
  @moduledoc "Recovery mail content; caller supplies the Rails-compatible public URL."
  alias Dawarich.Mail.ExploreFeatures
  @surfaces [:reset_password_instructions, :unlock_instructions]

  def build(kind, email, locale, raw, base_url, env) when kind in @surfaces do
    with :ok <- valid_url(base_url) do
      scope = "devise.mailer.#{kind}."

      t = fn key ->
        {:ok, value} = Dawarich.I18n.t(locale, scope <> key)
        value
      end

      path =
        if kind == :reset_password_instructions, do: "/users/password/edit", else: "/users/unlock"

      parameter =
        if kind == :reset_password_instructions, do: "reset_password_token", else: "unlock_token"

      url =
        String.trim_trailing(base_url, "/") <>
          path <> "?" <> URI.encode_query(%{parameter => raw})

      hello = t.("hello") <> " " <> email <> "!"
      {before_link, label, after_link} = paragraphs(kind)
      link = "<p><a href=\"#{h(url)}\">#{h(t.(label))}</a></p>\n"

      html =
        paragraph(hello) <>
          "\n" <>
          Enum.map_join(before_link, "\n", &paragraph(t.(&1))) <>
          "\n" <>
          link <>
          if(after_link == [],
            do: "",
            else: "\n" <> Enum.map_join(after_link, "", &paragraph(t.(&1)))
          )

      {:ok, subject} = Dawarich.I18n.t(locale, scope <> "subject")

      {:ok,
       %{
         from: env["SMTP_FROM"],
         reply_to: env["SMTP_FROM"],
         to: email,
         subject: subject,
         html: html,
         format: :html_only
       }}
    end
  end

  def build(_, _, _, _, _, _), do: {:error, :surface}

  def valid_base_url?(value), do: valid_url(value) == :ok

  defp paragraphs(:reset_password_instructions),
    do: {
      ["someone_has_requested_a_link_to_change_your_password_you"],
      "change_my_password",
      [
        "if_you_didn_t_request_this_please_ignore_this_email",
        "your_password_won_t_change_until_you_access_the_link"
      ]
    }

  defp paragraphs(:unlock_instructions),
    do: {
      [
        "your_account_has_been_locked_due_to_an_excessive_number",
        "click_the_link_below_to_unlock_your_account"
      ],
      "unlock_my_account",
      []
    }

  defp paragraph(text), do: "<p>#{h(text)}</p>\n"
  defp h(text), do: ExploreFeatures.h(text)

  defp valid_url(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host, userinfo: nil, query: nil, fragment: nil, path: path}
      when scheme in ["http", "https"] and is_binary(host) and host != "" and
             path in [nil, "", "/"] ->
        :ok

      _ ->
        {:error, :base_url}
    end
  end

  defp valid_url(_), do: {:error, :base_url}
end
