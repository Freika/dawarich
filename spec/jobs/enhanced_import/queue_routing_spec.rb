# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Enhanced import jobs are routed to a queue Sidekiq consumes' do
  let(:configured_queues) do
    YAML.load_file(Rails.root.join('config/sidekiq.yml'))[:queues].map(&:to_s)
  end

  [EnhancedImport::ExtractJob, EnhancedImport::DestroyJob].each do |job_class|
    it "#{job_class} runs on a queue listed in sidekiq.yml" do
      expect(configured_queues).to include(job_class.new.queue_name)
    end
  end
end
