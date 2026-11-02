-- chat_context: besides the 3 best general chunks, also hand the model the 3 best-matching PRODUCTS
-- (ingredients / features / price chunks) so it can recommend them with reasons.

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

  with ranked as materialized (
    select r.id, r.question, r.answer, r.category, r.url, r.score
    from private.rank_knowledge(nq) r
  ),
  general as (
    select id, question, answer, category, url, score
    from ranked where score >= 0.15 order by score desc limit 3
  ),
  prod_top as (
    select url, max(score) as ms
    from ranked
    where category = 'محصول' and url is not null and score >= 0.1
    group by url order by max(score) desc limit 3
  ),
  prod_rows as (
    select k.id, k.question, k.answer, k.category, k.url, pt.ms as score,
           row_number() over (
             partition by k.url
             order by case when k.question ~ '^ترکیبات' then 1
                           when k.question ~ '^ویژگی' then 2
                           when k.question ~ '^قیمت' then 3 else 4 end, k.id) as rn
    from public.knowledge k
    join prod_top pt on pt.url = k.url
    where k.category = 'محصول'
      and k.question ~ '^(ترکیبات|ویژگی|قیمت)'
  ),
  merged as (
    select id, question, left(answer, 700) as answer, category, url, score from general
    union
    select id, question, left(answer, 700), category, url, score from prod_rows where rn <= 3
  )
  select coalesce(jsonb_agg(to_jsonb(m) order by m.score desc, m.id), '[]'::jsonb),
         coalesce((select max(score) from general), 0)
    into rows_json, best
  from merged m;

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
