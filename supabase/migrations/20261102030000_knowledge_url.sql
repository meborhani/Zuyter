-- Each answer can link back to its page on zuyter.ir (product / article / FAQ).
alter table public.knowledge
  add column url text
  check (url is null or (char_length(url) <= 500 and url ~ '^https://(www\.)?zuyter\.ir/'));

drop function public.ask_skin(text);

create function public.ask_skin(q text)
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
    select s.id, s.question, s.answer, s.category, s.url, s.score
    from (
      select k.id, k.question, k.answer, k.category, k.url,
             greatest(
               extensions.similarity(nq, k.search_text),
               extensions.word_similarity(nq, k.search_text) * 0.9
             )::real as score
      from public.knowledge k
      where k.is_active
    ) s
    where s.score >= 0.30
    order by s.score desc
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
