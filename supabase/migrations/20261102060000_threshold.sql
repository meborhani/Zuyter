-- Match threshold tuned on real questions: relevant answers score >= 0.28, off-topic <= 0.15.
create or replace function public.ask_skin(q text)
returns table (id bigint, question text, answer text, category text, url text, score real)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  nq text;
begin
  q := left(btrim(coalesce(q, '')), 300);
  nq := private.normalize_fa(q);
  if char_length(nq) < 3 then
    return;
  end if;

  return query
    select r.id, r.question, r.answer, r.category, r.url, r.score
    from private.rank_knowledge(nq) r
    where r.score >= 0.25
    order by r.score desc
    limit 3;

  if not found then
    if (select count(*) from public.unanswered) < 3000 then
      insert into public.unanswered as u (question, question_norm)
      values (q, nq)
      on conflict (question_norm)
      do update set hits = u.hits + 1, last_asked = now();
    else
      update public.unanswered u
         set hits = u.hits + 1, last_asked = now()
       where u.question_norm = nq;
    end if;
  end if;
end;
$$;

revoke all on function public.ask_skin(text) from public, anon, authenticated;
grant execute on function public.ask_skin(text) to anon, authenticated;
