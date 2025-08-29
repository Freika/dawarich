# frozen_string_literal: true

class Jobs::Create
  class InvalidJobName < StandardError; end

  attr_reader :job_name, :user

  def initialize(job_name, user_id)
    @job_name = job_name
    @user = User.find(user_id)
  end

  def call
    points =
      case job_name
      when 'start_reverse_geocoding'
        user.points
      when 'continue_reverse_geocoding'
        user.points.not_reverse_geocoded
      else
        raise InvalidJobName, 'Invalid job name'
      end

    # TODO: bulk enqueue reverse geocoding with ActiveJob
    points.find_each(&:async_reverse_geocode)
  end
end
