-- Automatic cleanup of the "cache" (unanswered questions) for the free tier.
-- Runs daily via pg_cron. It NEVER touches public.knowledge (the owner's curated data).
--  1) resolved items older than 30 days are removed;
--  2) if the whole database passes max_db_bytes (default 400 MB, i.e. 80% of the free
--     500 MB limit), the OLDEST unanswered questions are deleted, keeping the newest keep_rows.

create extension if not exists pg_cron with schema pg_catalog;

create or replace function private.trim_cache(
  max_db_bytes bigint default 400 * 1024 * 1024,
  keep_rows int default 500
)
returns text
language plpgsql
set search_path = ''
as $$
declare
  db_bytes bigint := pg_database_size(current_database());
  del_resolved int := 0;
  del_old int := 0;
begin
  delete from public.unanswered
   where resolved and last_asked < now() - interval '30 days';
  get diagnostics del_resolved = row_count;

  if db_bytes > max_db_bytes then
    delete from public.unanswered u
     where u.id not in (
       select x.id from public.unanswered x order by x.last_asked desc limit keep_rows
     );
    get diagnostics del_old = row_count;
  end if;

  return format('db=%s MB, deleted_resolved=%s, deleted_oldest=%s',
                db_bytes / 1048576, del_resolved, del_old);
end;
$$;

revoke all on function private.trim_cache(bigint, int) from public, anon, authenticated;

select cron.schedule('trim-unanswered-cache', '0 3 * * *', $$select private.trim_cache()$$);
