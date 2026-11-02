-- chat_context v5: concern -> active ingredients -> Zuyter products containing them.
create or replace function private.concern_hits(nq text)
returns table(id int, hits int)
language sql
stable
set search_path = ''
as $$
  select i.id, count(*)::int
  from public.active_ingredient i, unnest(i.concerns) k
  where nq ~ ('(^| )' || private.normalize_fa(k))
  group by i.id
$$;

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
  ing_json jsonb;
  prod_json jsonb;
  best real;
  dry boolean;
  oily boolean;
begin
  q := left(btrim(coalesce(q, '')), 300);
  nq := private.normalize_fa(q);

  insert into private.chat_usage as u (day, k, n) values (current_date, 'global', 1)
    on conflict (day, k) do update set n = u.n + 1 returning n into g;
  insert into private.chat_usage as u (day, k, n) values (current_date, 'ip:' || left(coalesce(ip_hash, ''), 32), 1)
    on conflict (day, k) do update set n = u.n + 1 returning n into p;

  if g > global_cap or p > ip_cap then
    return jsonb_build_object('allowed', false);
  end if;

  if char_length(nq) < 3 then
    return jsonb_build_object('allowed', true, 'rows', '[]'::jsonb, 'ingredients', '[]'::jsonb, 'products', '[]'::jsonb);
  end if;

  dry  := nq ~ '(^| )(خشک|دهیدراته|کم آب)';
  oily := nq ~ '(^| )(چرب|مختلط)';

  -- 1) ingredients that help with the concern(s) named in the question
  select coalesce(jsonb_agg(jsonb_build_object('name', t.name, 'benefit', t.benefit, 'in_products', t.np) order by t.hits desc, t.np desc), '[]'::jsonb)
    into ing_json
  from (
    select i.name, i.benefit, h.hits,
           (select count(*) from public.product_active pa where pa.ingredient_id = i.id) as np
    from private.concern_hits(nq) h join public.active_ingredient i on i.id = h.id
    order by h.hits desc, 4 desc limit 6
  ) t;

  -- 2) Zuyter products containing those ingredients (skin type respected when the user states it)
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'title', x.title, 'price', x.price, 'url', x.url, 'matched', x.matched) order by x.sc desc), '[]'::jsonb)
    into prod_json
  from (
    select pi.knowledge_id as id, pi.title, pi.price, pi.url,
           sum(h.hits)::float / (1 + 0.15 * (select count(*) from public.product_active z where z.url = pi.url))
             + case when (dry and pi.skin_type = 'خشک') or (oily and pi.skin_type = 'چرب') then 1.5 else 0 end as sc,
           (select jsonb_agg(jsonb_build_object('name', i2.name, 'role', pa2.role_text) order by h2.hits desc)
              from public.product_active pa2
              join private.concern_hits(nq) h2 on h2.id = pa2.ingredient_id
              join public.active_ingredient i2 on i2.id = pa2.ingredient_id
             where pa2.url = pi.url) as matched
    from public.product_info pi
    join public.product_active pa on pa.url = pi.url
    join private.concern_hits(nq) h on h.id = pa.ingredient_id
    where pi.kind = 'single'
      and not (dry and not oily and pi.skin_type = 'چرب')
      and not (oily and not dry and pi.skin_type = 'خشک')
    group by pi.url, pi.knowledge_id, pi.title, pi.price, pi.skin_type
    order by 5 desc limit 3
  ) x;

  -- 3) general knowledge chunks (articles, FAQ); text-matched products only when no ingredient path applies
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
      and jsonb_array_length(prod_json) = 0
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
    where k.category = 'محصول' and k.question ~ '^(ترکیبات|ویژگی|قیمت)'
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

  if best < 0.25 and jsonb_array_length(ing_json) = 0
     and (select count(*) from public.unanswered) < 3000 then
    insert into public.unanswered as u (question, question_norm)
    values (q, nq)
    on conflict (question_norm) do update set hits = u.hits + 1, last_asked = now();
  end if;

  return jsonb_build_object('allowed', true, 'rows', rows_json, 'ingredients', ing_json, 'products', prod_json);
end;
$$;

revoke all on function public.chat_context(text, text, int, int) from public, anon, authenticated;
grant execute on function public.chat_context(text, text, int, int) to service_role;
