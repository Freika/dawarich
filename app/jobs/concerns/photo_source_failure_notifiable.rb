# frozen_string_literal: true

# For photo import jobs: a transport failure that a retry cannot fix (a refused
# redirect, a blocked address) is reported to the user instead of ending in a
# log line. Retryable failures are re-raised for the job's retry_on.
module PhotoSourceFailureNotifiable
  extend ActiveSupport::Concern

  private

  def report_photo_source_failure(user, source, error)
    raise error if error.retryable?

    I18n.with_locale(user.locale) do
      Notifications::Create.new(
        user: user,
        kind: :error,
        title: I18n.t("services.#{source}.import_geodata.import_was_not_created"),
        content: I18n.t("services.#{source}.connection_tester.#{source}_connection_failed_message",
                        message: error.message)
      ).call
    end
  end
end
