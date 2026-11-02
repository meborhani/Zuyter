-- Better Persian matching:
--  * spelling unification (e.g. "نیاسین آمید" -> "نیاسینامید", "ضد جوش" -> "ضدجوش")
--  * more colloquial stopwords (چیه، میشه، داره، سلام ...)
--  * ranking = trigram similarity gated by weighted word coverage (rare words like "چرب"/"خشک"
--    count more than common ones like "پوست"), so oily/dry mix-ups are penalized.
-- After changing normalize_fa run:  update public.knowledge set question = question;

create or replace function private.normalize_fa(t text)
returns text
language plpgsql
immutable
parallel safe
set search_path = ''
as $$
declare
  x text;
begin
  x := translate(
         lower(coalesce(t, '')),
         'يكۀةأإآ٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹',
         'یکههااا01234567890123456789'
       );
  x := regexp_replace(x, '[ً-ٰٟـ]', '', 'g');   -- diacritics, tatweel
  x := regexp_replace(x, '[‌‎‏]', ' ', 'g');         -- ZWNJ and direction marks
  x := regexp_replace(x, '[^[:alnum:][:space:]]+', ' ', 'g');       -- punctuation
  x := regexp_replace(x, '\s+', ' ', 'g');
  x := regexp_replace(x, 'نیاسین ?امید', 'نیاسینامید', 'g');
  x := regexp_replace(x, 'الفا ?اربوتین', 'الفااربوتین', 'g');
  x := regexp_replace(x, '(^|\s)ضد\s+', '\1ضد', 'g');
  x := regexp_replace(
         x,
         '(^|\s)(?:چه|چطور|چطوری|چگونه|آیا|است|را|رو|از|به|در|که|و|با|برای|این|آن|یک|می|های|ها|هم|تا|یا|اگر|چرا|کی|کجا|چند|چنده|کدام|باید|من|کنم|کنیم|کنید|کند|کرد|شود|شد|باشد|بود|دارد|دارم|هست|هستم|نیست|چیه|چیست|میشه|شه|بشه|داره|دارن|دارید|هستن|هستند|ای|چیکار|چکار|لطفا|ممنون|سلام)(?=\s|$)',
         ' ', 'g'
       );
  return btrim(regexp_replace(x, '\s+', ' ', 'g'));
end;
$$;

-- All rows with a score (no threshold, no logging). Internal only.
create or replace function private.rank_knowledge(nq text)
returns table (id bigint, question text, answer text, category text, url text, score real)
language plpgsql
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  n_docs int;
begin
  select count(*) into n_docs from public.knowledge where is_active;

  return query
  with toks as (
    select distinct tk from unnest(string_to_array(nq, ' ')) as tk where char_length(tk) >= 2
  ),
  w as (
    select toks.tk,
           ln((n_docs + 1.0) / (
             (select count(*) from public.knowledge k
               where k.is_active and position(' ' || toks.tk || ' ' in ' ' || k.search_text || ' ') > 0) + 1.0
           )) as wt
    from toks
  ),
  tot as (select greatest(sum(w.wt), 0.0001) as s from w),
  scored as (
    select k.id, k.question, k.answer, k.category, k.url,
           greatest(
             extensions.similarity(nq, k.search_text),
             extensions.word_similarity(nq, k.search_text) * 0.9
           ) as base,
           coalesce((select sum(w.wt) from w
                      where position(' ' || w.tk || ' ' in ' ' || k.search_text || ' ') > 0), 0)
             / (select s from tot) as cov
    from public.knowledge k
    where k.is_active
  )
  select s.id, s.question, s.answer, s.category, s.url,
         (s.base * (0.25 + 0.75 * s.cov))::real as score
  from scored s;
end;
$$;

revoke all on function private.rank_knowledge(text) from public, anon, authenticated;

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
    where r.score >= 0.28
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
