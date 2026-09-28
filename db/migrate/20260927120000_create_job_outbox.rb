# frozen_string_literal: true

class CreateJobOutbox < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE job_outbox (
        event_id uuid PRIMARY KEY,
        command_type character varying NOT NULL,
        command_version integer NOT NULL,
        payload jsonb NOT NULL,
        metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
        aggregate_id bigint,
        dedupe_key character varying,
        scheduled_at timestamp with time zone NOT NULL,
        state character varying NOT NULL DEFAULT 'pending',
        oban_job_id bigint,
        error_code character varying,
        created_at timestamp with time zone NOT NULL DEFAULT now(),
        dispatched_at timestamp with time zone,
        CONSTRAINT job_outbox_command_version_positive CHECK (command_version > 0),
        CONSTRAINT job_outbox_payload_object CHECK (jsonb_typeof(payload) = 'object' AND octet_length(payload::text) <= 8192),
        CONSTRAINT job_outbox_state_known CHECK (state IN ('pending', 'dispatched', 'quarantined'))
      );
      CREATE INDEX index_job_outbox_on_due ON job_outbox (scheduled_at, event_id) WHERE state = 'pending';
      CREATE UNIQUE INDEX index_job_outbox_on_pending_dedupe ON job_outbox (command_type, dedupe_key) WHERE state = 'pending' AND dedupe_key IS NOT NULL;
    SQL
  end

  def down
    drop_table :job_outbox
  end
end
