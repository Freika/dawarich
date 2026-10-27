# frozen_string_literal: true

class Users::Digests::RequestYear
  def initialize(user, year)
    @user = user
    @year = year
  end

  def call
    @user.with_lock do
      digest = @user.digests.yearly.find_or_create_by!(year: @year)
      digest.with_lock do
        unless digest.generation_pending?
          digest.update!(generation_status: :queued)
          Users::Digests::Yearly::CalculatingJob.perform_later(@user.id, @year)
        end
      end
      digest
    end
  end
end
