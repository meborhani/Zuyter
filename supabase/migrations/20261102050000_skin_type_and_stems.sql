-- Ranking v3:
--  * skin-type guard: a query about oily skin must not return a dry-skin answer (and vice versa)
--  * light stemming: "پوستم" matches "پوست", "چربی" matches "چرب"
--  * colloquial clitics ("محصولاتتون"), digit/letter splitting ("۱۰نیاسین"), مصرف == استفاده
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
  x := regexp_replace(x, '(\d)([^\d\s])', '\1 \2', 'g');            -- 10نیاسین -> 10 نیاسین
  x := regexp_replace(x, '([^\d\s])(\d)', '\1 \2', 'g');
  x := regexp_replace(x, '\s+', ' ', 'g');
  x := regexp_replace(x, 'نیاسین ?امید', 'نیاسینامید', 'g');
  x := regexp_replace(x, 'الفا ?اربوتین', 'الفااربوتین', 'g');
  x := regexp_replace(x, '(^|\s)ضد\s+', '\1ضد', 'g');
  x := regexp_replace(x, 'مصرف', 'استفاده', 'g');
  x := regexp_replace(x, '(^|\s)همش(?=\s|$)', '\1همیشه', 'g');
  x := regexp_replace(x, '(\S{3,})(تون|شون|مون)(?=\s|$)', '\1', 'g');  -- محصولاتتون -> محصولات
  x := regexp_replace(
         x,
         '(^|\s)(?:چه|چطور|چطوری|چگونه|آیا|است|را|رو|از|به|در|که|و|با|برای|این|آن|یک|می|های|ها|هم|تا|یا|اگر|چرا|کی|کجا|چند|چنده|کدام|باید|من|کنم|کنیم|کنید|کند|کرد|شود|شد|باشد|بود|دارد|دارم|هست|هستم|نیست|چیه|چیست|میشه|شه|بشه|داره|دارن|دارید|هستن|هستند|ای|چیکار|چکار|لطفا|ممنون|سلام)(?=\s|$)',
         ' ', 'g'
       );
  return btrim(regexp_replace(x, '\s+', ' ', 'g'));
end;
$$;

-- token match: long words match by prefix (پوستم ~ پوست), short words must match exactly.
create or replace function private.tok_in(tk text, txt text)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case when char_length(tk) >= 5
              then position(' ' || left(tk, char_length(tk) - 1) in ' ' || txt) > 0
              else position(' ' || tk || ' ' in ' ' || txt || ' ') > 0
         end;
$$;

-- skin types mentioned in a text (dehydrated counts as dry).
create or replace function private.skin_types(txt text)
returns text[]
language sql
immutable
parallel safe
set search_path = ''
as $$
  select array_remove(array[
    case when position(' چرب' in ' ' || txt) > 0 then 'چرب' end,
    case when position(' خشک' in ' ' || txt) > 0 or position(' دهیدرات' in ' ' || txt) > 0 then 'خشک' end,
    case when position(' حساس' in ' ' || txt) > 0 then 'حساس' end,
    case when position(' مختلط' in ' ' || txt) > 0 then 'مختلط' end
  ], null);
$$;

create or replace function private.rank_knowledge(nq text)
returns table (id bigint, question text, answer text, category text, url text, score real)
language plpgsql
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  n_docs int;
  qt text[] := private.skin_types(nq);
begin
  select count(*) into n_docs from public.knowledge where is_active;

  return query
  with toks as (
    select distinct tk from unnest(string_to_array(nq, ' ')) as tk where char_length(tk) >= 2
  ),
  w as (
    select toks.tk,
           -- weight = rarity of the word; unknown words are capped (they may be colloquial forms)
           least(
             ln((n_docs + 1.0) / (
               (select count(*) from public.knowledge k
                 where k.is_active and private.tok_in(toks.tk, k.search_text)) + 1.0
             )),
             ln((n_docs + 1.0) / 15.0)
           ) as wt
    from toks
  ),
  tot as (select greatest(sum(w.wt), 0.0001) as s from w),
  scored as (
    select k.id, k.question, k.answer, k.category, k.url,
           greatest(
             extensions.similarity(nq, k.search_text),
             extensions.word_similarity(nq, k.search_text) * 0.9
           ) as base,
           coalesce((select sum(w.wt) from w where private.tok_in(w.tk, k.search_text)), 0)
             / (select s from tot) as cov,
           private.skin_types(k.search_text) as dt
    from public.knowledge k
    where k.is_active
  )
  select s.id, s.question, s.answer, s.category, s.url,
         (s.base * (0.25 + 0.75 * s.cov)
            * case when cardinality(qt) > 0 and cardinality(s.dt) > 0 and not (qt && s.dt)
                   then 0.35 else 1.0 end)::real as score
  from scored s;
end;
$$;

revoke all on function private.rank_knowledge(text) from public, anon, authenticated;
revoke all on function private.tok_in(text, text) from public, anon, authenticated;
revoke all on function private.skin_types(text) from public, anon, authenticated;
