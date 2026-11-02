-- Context retrieval + daily usage caps for the LLM chat edge function.
-- Callable ONLY by service_role (the edge function), never from the browser.

create table if not exists private.chat_usage (
  day date not null default current_date,
  k   text not null,
  n   int  not null default 0,
  primary key (day, k)
);
alter table private.chat_usage enable row level security;

create or replace function public.chat_context(q text, ip_hash text, global_cap int default 400, ip_cap int default 60)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  nq text;
  g int;
  p int;
  rows_json jsonb;
  best real;
begin
  q := left(btrim(coalesce(q, '')), 300);
  nq := private.normalize_fa(q);

  insert into private.chat_usage as u (day, k, n) values (current_date, 'global', 1)
    on conflict (day, k) do update set n = u.n + 1 returning n into g;
  insert into private.chat_usage as u (day, k, n) values (current_date, 'ip:' || left(coalesce(ip_hash, ''), 32), 1)
    on conflict (day, k) do update set n = u.n + 1 returning n into p;

  if g > global_cap or p > ip_cap then
    return jsonb_build_object('allowed', false, 'rows', '[]'::jsonb);
  end if;

  if char_length(nq) < 3 then
    return jsonb_build_object('allowed', true, 'rows', '[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(to_jsonb(t) order by t.score desc), '[]'::jsonb), coalesce(max(t.score), 0)
    into rows_json, best
  from (
    select r.id, r.question, left(r.answer, 1200) as answer, r.category, r.url, r.score
    from private.rank_knowledge(nq) r
    where r.score >= 0.15
    order by r.score desc
    limit 4
  ) t;

  if best < 0.25 and (select count(*) from public.unanswered) < 3000 then
    insert into public.unanswered as u (question, question_norm)
    values (q, nq)
    on conflict (question_norm) do update set hits = u.hits + 1, last_asked = now();
  end if;

  return jsonb_build_object('allowed', true, 'rows', rows_json);
end;
$$;

revoke all on function public.chat_context(text, text, int, int) from public, anon, authenticated;
grant execute on function public.chat_context(text, text, int, int) to service_role;

-- old usage rows are tiny, but keep the table clean
create or replace function private.trim_chat_usage() returns void
language sql security definer set search_path = '' as
$$ delete from private.chat_usage where day < current_date - 7; $$;
