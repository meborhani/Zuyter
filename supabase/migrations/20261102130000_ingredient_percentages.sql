-- Concentrations from the owner's formulation sheets. Only whole-number percentages of key actives are stored
-- (decimals in the sheets use an ambiguous "5/0" notation and are deliberately left out).
alter table public.product_active add column if not exists percent int;

update public.product_active pa
   set percent = v.pct,
       role_text = coalesce(pa.role_text, i.name) || ' (غلظت در فرمول: ' || translate(v.pct::text, '0123456789', '۰۱۲۳۴۵۶۷۸۹') || '٪)'
  from (values
    ('oily-combination-skin-hydratin-zuyter', 'نیاسینامید', 2),
    ('acne-serum-oily-skin-zuyter',           'نیاسینامید', 10),
    ('acne-serum-oily-skin-zuyter',           'کافئین', 1),
    ('acne-serum-oily-skin-zuyter',           'زینک PCA', 1),
    ('anti-dark-spot-brightening-serum-zuyter','نیاسینامید', 3),
    ('anti-dark-spot-brightening-serum-zuyter','آلفا آربوتین', 2),
    ('anti-dark-spot-brightening-serum-zuyter','کافئین', 1),
    ('anti-dark-spot-brightening-serum-zuyter','زینک PCA', 1),
    ('anti-wrinkle-brightening-eye-serum-zuyter','نیاسینامید', 2),
    ('anti-wrinkle-brightening-eye-serum-zuyter','زینک PCA', 1),
    ('dry-skin-hydrating-serum-zuyter',       'نیاسینامید', 2),
    ('dry-skin-hydrating-serum-zuyter',       'زینک PCA', 1),
    ('oily-combination-skin-toner-zuyter',    'نیاسینامید', 2),
    ('oily-combination-skin-toner-zuyter',    'اسید سالیسیلیک', 1),
    ('oily-combination-skin-toner-zuyter',    'زینک PCA', 1),
    ('dry-skin-toner-zuyter',                 'نیاسینامید', 2),
    ('dry-skin-toner-zuyter',                 'زینک PCA', 1),
    ('dry-skin-hydrating-cream-zuyter',       'کافئین', 1)
  ) as v(slug, ing, pct)
  join public.active_ingredient i on i.name like v.ing || '%'
 where pa.ingredient_id = i.id
   and pa.url = 'https://zuyter.ir/product/' || v.slug || '/'
   and pa.percent is null;
