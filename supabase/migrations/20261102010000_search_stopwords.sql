-- Improve matching of informal Persian questions by dropping very common words
-- (question words, pronouns, light verbs). Applied to both query and stored text.
-- NOTE: after changing this function, refresh stored search_text with:
--   update public.knowledge set question = question;

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
        s.x,
        '(^|\s)(?:چه|چطور|چطوری|چگونه|آیا|است|را|رو|از|به|در|که|و|با|برای|این|آن|یک|می|های|ها|هم|تا|یا|اگر|چرا|کی|کجا|چند|چنده|کدام|باید|من|کنم|کنیم|کنید|کند|کرد|شود|شد|باشد|بود|دارد|دارم|هست|هستم|نیست)(?=\s|$)',
        ' ', 'g'
      ),
      '\s+', ' ', 'g'
    )
  )
  from (
    select regexp_replace(
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
    ) as x
  ) s;
$$;
