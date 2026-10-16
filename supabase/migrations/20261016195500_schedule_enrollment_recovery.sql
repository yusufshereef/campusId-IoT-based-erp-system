create extension if not exists pg_cron with schema pg_catalog;

select cron.schedule(
  'campusid-stale-enrollment-recovery',
  '* * * * *',
  $recovery$
    update public.device_commands
    set status = 'failed',
        completed_at = now(),
        updated_at = now(),
        error_message = case
          when status = 'processing'
            then 'Terminal confirmation timed out; inspect sensor before retry'
          else 'Terminal did not claim command before timeout; retry enrollment'
        end
    where command_type = 'ENROLL_FINGERPRINT'
      and status in ('pending', 'processing')
      and coalesce(claimed_at, created_at) < now() - interval '10 minutes';
  $recovery$
);
