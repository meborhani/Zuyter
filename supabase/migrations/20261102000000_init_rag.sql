-- Zuyter Skin: Persian RAG knowledge base (free-tier friendly, no embeddings)
-- Search = Persian normalization + pg_trgm similarity.

create extension if not exists pg_trgm with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- Normalizes Persian/Arabic text so that different spellings match:
-- Arabic ي/ك -> ی/ک, digits -> latin, removes diacritics, ZWNJ -> space, strips punctuation.
create or replace function private.normalize_fa(t text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select btrim(
    regexp_replace(
      regexp_replace(
        regexp_replace(
          regexp_replace(
            translate(
              lower(coalesce(t, '')),
              'يكۀةأإآ٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹',
              'یکههااا01234567890123456789'
            ),
            '[ً-ٰٟـ]', '', 'g'
          ),
          '[‌‎‏]', ' ', 'g'
        ),
        '[^[:alnum:][:space:]]+', ' ', 'g'
      ),
      '\s+', ' ', 'g'
    )
  );
$$;

-- Owner-managed knowledge (edit via Supabase Table Editor).
create table public.knowledge (
  id bigint generated always as identity primary key,
  question text not null check (char_length(question) between 3 and 300),
  answer text not null check (char_length(answer) between 1 and 4000),
  keywords text check (char_length(keywords) <= 500),
  category text check (char_length(category) <= 60),
  is_active boolean not null default true,
  search_text text generated always as (
    private.normalize_fa(question || ' ' || coalesce(keywords, ''))
  ) stored,
  created_at timestamptz not null default now()
);

-- Questions the system could not answer (so the owner can add answers).
create table public.unanswered (
  id bigint generated always as identity primary key,
  question text not null check (char_length(question) <= 300),
  question_norm text not null unique,
  hits int not null default 1,
  resolved boolean not null default false,
  first_asked timestamptz not null default now(),
  last_asked timestamptz not null default now()
);

-- RLS on, no policies: the public API cannot touch the tables directly.
alter table public.knowledge enable row level security;
alter table public.unanswered enable row level security;
revoke all on public.knowledge from anon, authenticated;
revoke all on public.unanswered from anon, authenticated;

-- The only public entry point.
create or replace function public.ask_skin(q text)
returns table (id bigint, question text, answer text, category text, score real)
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
    select s.id, s.question, s.answer, s.category, s.score
    from (
      select k.id, k.question, k.answer, k.category,
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
    -- Cap stored unanswered questions to protect the free-tier quota.
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
