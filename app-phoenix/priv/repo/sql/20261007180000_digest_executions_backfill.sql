DO $$
BEGIN
INSERT INTO phoenix.digest_executions(effect,user_id,year,month,state,outcome,legacy)
SELECT CASE WHEN d.period_type=0 THEN 'digests.calculate_month' ELSE 'digests.calculate_year' END,
       d.user_id, d.year, CASE WHEN d.period_type=0 THEN d.month ELSE 0 END,
       CASE WHEN d.sent_at IS NOT NULL OR EXISTS (
         SELECT 1 FROM phoenix.rails_commands m
         WHERE m.kind=CASE WHEN d.period_type=0 THEN 'digests.email_month' ELSE 'digests.email_year' END
           AND m.payload->>'user_id'=d.user_id::text AND m.payload->>'year'=d.year::text
           AND (d.period_type=1 OR m.payload->>'month'=d.month::text)
       ) THEN 'published' ELSE 'generated' END, 'mail', true
FROM public.digests d
WHERE d.period_type IN (0,1) AND (d.period_type=1 OR d.month IS NOT NULL)
ON CONFLICT(effect,user_id,year,month) DO NOTHING;

IF to_regclass('public.job_outbox') IS NOT NULL THEN
  IF has_table_privilege('public.job_outbox','SELECT') THEN
    UPDATE phoenix.digest_executions e SET state='published'
    WHERE e.legacy AND e.state<>'published' AND EXISTS (
      SELECT 1 FROM public.job_outbox m
      WHERE m.command_type=CASE WHEN e.effect='digests.calculate_month' THEN 'mail.digest.monthly' ELSE 'mail.digest.yearly' END
        AND m.payload->>'user_id'=e.user_id::text AND m.payload->>'year'=e.year::text
        AND (e.month=0 OR m.payload->>'month'=e.month::text)
    );
  END IF;
END IF;
END $$;
