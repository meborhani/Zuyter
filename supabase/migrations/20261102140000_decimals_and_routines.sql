-- Product type (فوم/تونر/سرم/کرم) for routine suggestions + decimal concentrations from the formula sheets.
-- Sheets write 0.5 as "5/0" and 1.5 as "5/1" (digits reversed). Only unambiguous single-digit forms are used;
-- multi-digit forms like "15/0" or "05/0" are skipped on purpose.
alter table public.product_info add column if not exists ptype text;
update public.product_info set ptype = case
  when title like '%فوم%' then 'فوم'
  when title like '%تونر%' then 'تونر'
  when title like '%سرم%' then 'سرم'
  when title like '%کرم%' then 'کرم' end
 where ptype is null;

alter table public.product_active alter column percent type numeric(6,2);

update public.product_active pa
   set percent = v.pct,
       role_text = coalesce(pa.role_text, i.name) || ' (غلظت در فرمول: '
                   || translate(replace(trim_scale(v.pct)::text, '.', '٫'), '0123456789', '۰۱۲۳۴۵۶۷۸۹') || '٪)'
  from (values
    ('oily-combination-skin-hydratin-zuyter','هیالورونیک اسید',0.1),
    ('oily-combination-skin-hydratin-zuyter','شی باتر',0.5),
    ('oily-combination-skin-hydratin-zuyter','ویتامین E',0.3),
    ('oily-combination-skin-hydratin-zuyter','ویتامین A',0.2),
    ('oily-combination-skin-hydratin-zuyter','گلیسرین',3),
    ('dry-skin-hydrating-cream-zuyter','هیالورونیک اسید',0.1),
    ('dry-skin-hydrating-cream-zuyter','شی باتر',0.5),
    ('dry-skin-hydrating-cream-zuyter','ویتامین E',0.3),
    ('dry-skin-hydrating-cream-zuyter','ویتامین A',0.2),
    ('acne-serum-oily-skin-zuyter','هیالورونیک اسید',0.2),
    ('acne-serum-oily-skin-zuyter','گلیسرین',1),
    ('acne-serum-oily-skin-zuyter','اسید لاکتیک',0.5),
    ('anti-dark-spot-brightening-serum-zuyter','هیالورونیک اسید',0.2),
    ('anti-dark-spot-brightening-serum-zuyter','گلیسرین',1),
    ('anti-dark-spot-brightening-serum-zuyter','عصاره درخت چای',1),
    ('anti-dark-spot-brightening-serum-zuyter','اسید لاکتیک',0.2),
    ('anti-wrinkle-brightening-eye-serum-zuyter','هیالورونیک اسید',0.5),
    ('anti-wrinkle-brightening-eye-serum-zuyter','کلاژن',0.2),
    ('anti-wrinkle-brightening-eye-serum-zuyter','کافئین',0.6),
    ('anti-wrinkle-brightening-eye-serum-zuyter','عصاره آرنیکا',2),
    ('anti-wrinkle-brightening-eye-serum-zuyter','گلیسرین',1),
    ('anti-wrinkle-brightening-eye-serum-zuyter','عصاره درخت چای',1),
    ('dry-skin-hydrating-serum-zuyter','هیالورونیک اسید',0.5),
    ('dry-skin-hydrating-serum-zuyter','کلاژن',0.2),
    ('dry-skin-hydrating-serum-zuyter','کافئین',0.6),
    ('dry-skin-hydrating-serum-zuyter','گلیسرین',1),
    ('dry-skin-hydrating-serum-zuyter','عصاره درخت چای',1),
    ('oily-combination-skin-toner-zuyter','اوره',1),
    ('oily-combination-skin-toner-zuyter','گلیسرین',1),
    ('oily-combination-skin-toner-zuyter','عصاره درخت چای',2),
    ('oily-combination-skin-toner-zuyter','اسید لاکتیک',0.5),
    ('dry-skin-toner-zuyter','اوره',1),
    ('dry-skin-toner-zuyter','گلیسرین',1),
    ('dry-skin-toner-zuyter','عصاره درخت چای',2),
    ('dry-skin-toner-zuyter','اسید لاکتیک',0.5),
    ('oily-combination-skin-facewash-zuyter','گلیسرین',4),
    ('oily-combination-skin-facewash-zuyter','زینک PCA',0.5),
    ('oily-combination-skin-facewash-zuyter','عصاره درخت چای',1.5),
    ('oily-combination-skin-facewash-zuyter','اسید لاکتیک',0.5),
    ('oily-combination-skin-facewash-zuyter','آلانتوئین',0.5),
    ('dry-dehydrated-skin-face-wash-foam-zuyter','گلیسرین',3),
    ('dry-dehydrated-skin-face-wash-foam-zuyter','زینک PCA',0.5),
    ('dry-dehydrated-skin-face-wash-foam-zuyter','عصاره درخت چای',1.5),
    ('dry-dehydrated-skin-face-wash-foam-zuyter','اسید لاکتیک',0.5),
    ('dry-dehydrated-skin-face-wash-foam-zuyter','آلانتوئین',0.5)
  ) as v(slug, ing, pct)
  join public.active_ingredient i on i.name like v.ing || '%'
 where pa.ingredient_id = i.id
   and pa.url = 'https://zuyter.ir/product/' || v.slug || '/'
   and pa.percent is null;

-- chat_context v6 (up to 4 products, one per type) is applied in the live project; see the function in the
-- Supabase dashboard (public.chat_context) — it returns {allowed, rows, ingredients, products[id,type,title,price,url,matched]}.
