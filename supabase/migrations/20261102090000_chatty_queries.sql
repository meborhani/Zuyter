-- Chatty questions ("میتونی کمکم کنی پوستم خشک نشه") must reduce to their skin keywords.
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
  x := regexp_replace(x, '[ً-ٰٟـ]', '', 'g');
  x := regexp_replace(x, '[‌‎‏]', ' ', 'g');
  x := regexp_replace(x, '[^[:alnum:][:space:]]+', ' ', 'g');
  x := regexp_replace(x, '(\d)([^\d\s])', '\1 \2', 'g');
  x := regexp_replace(x, '([^\d\s])(\d)', '\1 \2', 'g');
  x := regexp_replace(x, '\s+', ' ', 'g');
  x := regexp_replace(x, 'نیاسین ?امید', 'نیاسینامید', 'g');
  x := regexp_replace(x, 'الفا ?اربوتین', 'الفااربوتین', 'g');
  x := regexp_replace(x, '(^|\s)ضد\s+', '\1ضد', 'g');
  x := regexp_replace(x, 'مصرف', 'استفاده', 'g');
  x := regexp_replace(x, '(^|\s)همش(?=\s|$)', '\1همیشه', 'g');
  x := regexp_replace(x, '(\S{3,})(تون|شون|مون)(?=\s|$)', '\1', 'g');
  x := regexp_replace(x, '(^|\s)(پوست|صورت|لب|چشم|مو|دست|بدن|گردن|پیشانی|بینی|گونه)(م|ت|ش)(?=\s|$)', '\1\2', 'g');
  x := regexp_replace(
         x,
         '(^|\s)(?:چه|چطور|چطوری|چگونه|آیا|است|را|رو|از|به|در|که|و|با|برای|این|آن|یک|می|های|ها|هم|تا|یا|اگر|چرا|کی|کجا|چند|چنده|کدام|باید|من|کنم|کنیم|کنید|کند|کرد|شود|شد|باشد|بود|دارد|دارم|هست|هستم|نیست|چیه|چیست|میشه|شه|بشه|داره|دارن|دارید|هستن|هستند|ای|چیکار|چکار|لطفا|ممنون|سلام|خوبی|خوبین|خوبید|خوب|خوبه|عزیزم|جونم|مرسی|درود|میتونی|میتونید|میتوانی|میتوانید|می‌تونی|کمک|کمکم|کنی|نشه|نمیشه|بگو|بگید|ببخشید|راستش|خب|خیلی|یه|تو|شما|اینه|هستش|لطفاً|فقط)(?=\s|$)',
         ' ', 'g'
       );
  return btrim(regexp_replace(x, '\s+', ' ', 'g'));
end;
$$;
