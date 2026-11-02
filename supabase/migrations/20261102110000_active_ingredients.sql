-- Active-ingredient knowledge: concern -> ingredients -> Zuyter products that contain them.
-- Ingredient benefits are short general descriptions in the owner's own wording; edit the rows to taste.
create table if not exists public.active_ingredient (
  id       serial primary key,
  name     text not null unique,
  aliases  text[] not null,          -- spellings used to find it in product ingredient lists
  benefit  text not null,
  concerns text[] not null           -- word-start keywords of skin concerns it helps with
);
create table if not exists public.product_info (
  url          text primary key,
  knowledge_id bigint not null,      -- the "قیمت و مشخصات" row (used for the link)
  title        text not null,
  price        text,
  kind         text not null default 'single',   -- single | kit
  skin_type    text                              -- خشک | چرب | null (any / eye care)
);
create table if not exists public.product_active (
  url           text not null references public.product_info(url) on delete cascade,
  ingredient_id int  not null references public.active_ingredient(id) on delete cascade,
  role_text     text,                -- the owner's own sentence about it in that product
  primary key (url, ingredient_id)
);
alter table public.active_ingredient enable row level security;
alter table public.product_info enable row level security;
alter table public.product_active enable row level security;
revoke all on public.active_ingredient, public.product_info, public.product_active from anon, authenticated;

insert into public.active_ingredient (name, aliases, benefit, concerns) values
('نیاسینامید (ویتامین B3)', array['نیاسین‌آمید'], 'کمک به کاهش لک و یکدست شدن رنگ پوست، تنظیم ترشح چربی (سبوم) و کم‌تر دیده شدن منافذ، تقویت سد دفاعی پوست و کمک به بهبود جای جوش', array['لک','کدر','تیرگی','روشن','یکدست','جوش','آکنه','چرب','منافذ','سبوم','سد','براق']),
('آلفا آربوتین', array['آلفا آربوتین'], 'کنترل تولید ملانین و کمک به کاهش لک‌های تیره و ناهماهنگی رنگ پوست', array['لک','تیرگی','ملانین','کدر','روشن','قهوه','آفتاب','ناهمگون','یکدست']),
('اسید سالیسیلیک', array['اسید سالیسیلیک'], 'لایه‌بردار ملایم که به پاکسازی منافذ و پیشگیری از جوش کمک می‌کند', array['جوش','آکنه','منافذ','سرسیاه','چرب','سیاه','مختلط']),
('زینک PCA', array['زینک PCA'], 'کمک به تنظیم چربی پوست، کاهش براقیت و کاهش جوش و التهاب', array['چرب','جوش','آکنه','براق','سبوم','التهاب','مختلط']),
('عصاره درخت چای', array['عصاره درخت چای'], 'کمک به پاکسازی پوست، کنترل چربی و کاهش جوش‌ها و التهاب‌های پوستی', array['جوش','آکنه','چرب','التهاب','مختلط']),
('اسید لاکتیک', array['اسید لاکتیک'], 'لایه‌بردار ملایم برای حذف سلول‌های مرده، بهبود بافت و افزایش شفافیت پوست', array['زبر','بافت','کدر','شفاف','سلول','منافذ','خشک','پوسته']),
('هیالورونیک اسید', array['هیالورونیک اسید','سدیم هیالورونات'], 'آبرسان عمقی که رطوبت را در لایه‌های پوست نگه می‌دارد؛ کمک به جلوگیری از کم‌آبی و کاهش خطوط ریز ناشی از خشکی', array['خشک','دهیدراته','کم آب','کم‌آب','کشیده','خط','چروک','آبرسان','آبرسانی','رطوبت','ریز']),
('گلیسرین', array['گلیسرین'], 'رطوبت‌رسان مؤثر که به جذب و حفظ آب در پوست و جلوگیری از خشکی کمک می‌کند', array['خشک','دهیدراته','کشیده','آبرسان','آبرسانی','رطوبت','پوسته','شستشو']),
('اوره', array['اوره'], 'نرم‌کننده و آبرسان برای کاهش خشکی و زبری پوست', array['خشک','زبر','پوسته','کشیده','آبرسان','رطوبت','سرما']),
('شی باتر', array['شی باتر'], 'ماده‌ی مغذی که به تغذیه و نرمی پوست خشک و کاهش زبری و پوسته‌پوسته شدن کمک می‌کند', array['خشک','زبر','پوسته','سرما','زمستان','پاییز','ترک','تغذیه']),
('سدیم PCA', array['سدیم PCA'], 'آبرسان طبیعی پوست برای حفظ رطوبت و جلوگیری از دهیدراته شدن', array['خشک','دهیدراته','کم آب','آبرسان','آبرسانی','رطوبت']),
('ویتامین B5 (پانتنول)', array['ویتامین B5'], 'کمک به ترمیم و بازسازی پوست و افزایش نرمی و لطافت آن', array['خشک','ترمیم','حساس','تحریک','سد','زبر','بازسازی','پوسته']),
('آلوئه‌ورا', array['آلوئه‌ورا'], 'تسکین‌دهنده و آبرسان که به کاهش قرمزی، حساسیت و التهاب پوست کمک می‌کند', array['حساس','قرمز','التهاب','تحریک','خشک','آفتاب‌سوز','سوزش','آرام']),
('عصاره گل سرخ', array['عصاره گل سرخ'], 'کمک به آرامش پوست و کاهش احساس التهاب، قرمزی و حساسیت', array['حساس','قرمز','التهاب','تحریک','آرام','سوزش']),
('عصاره خیار', array['عصاره خیار'], 'ایجاد حس طراوت و خنکی و کمک به تسکین و شادابی پوست', array['حساس','خسته','طراوت','آرام','سوزش']),
('ویتامین E', array['ویتامین E'], 'آنتی‌اکسیدان برای محافظت از پوست در برابر عوامل محیطی و کمک به حفظ رطوبت', array['چروک','پیری','محیط','آلودگی','خشک','آنتی','پیر']),
('ویتامین A', array['ویتامین A'], 'کمک به بازسازی پوست و بهبود بافت و ظاهر کلی آن', array['چروک','پیری','بافت','بازسازی','خط','پیر','زبر']),
('کافئین', array['کافئین'], 'کمک به کاهش پف و تیرگی دور چشم، افزایش شادابی و کاهش ظاهر خسته‌ی پوست', array['پف','دورچشم','دور چشم','زیر چشم','زیرچشم','خسته','تیرگی','گود','کدر']),
('کلاژن', array['کلاژن'], 'کمک به بهبود خاصیت ارتجاعی و کاهش خطوط ریز دور چشم', array['چروک','خط','دورچشم','دور چشم','زیر چشم','زیرچشم','پیری','شل','پیر']),
('عصاره آرنیکا', array['عصاره آرنیکا'], 'کمک به کاهش پف و بهبود ظاهر خسته و کبود اطراف چشم', array['پف','کبود','دورچشم','دور چشم','زیر چشم','زیرچشم','خسته','گود']),
('آلانتوئین', array['آلانتوئین'], 'ترمیم‌کننده و تسکین‌دهنده برای کاهش تحریکات پوستی', array['حساس','تحریک','التهاب','ترمیم','سوزش','قرمز'])
on conflict (name) do nothing;

-- products (single products + kits)
insert into public.product_info (url, knowledge_id, title, price, kind, skin_type)
select k.url, k.id,
       left(btrim(regexp_replace(k.question, '^قیمت و مشخصات\s*', '')), 140),
       substring(k.answer from 'قیمت:\s*([^\n]+?)\s*تومان'),
       case when k.question ~ 'قیمت و مشخصات\s*پک' then 'kit' else 'single' end,
       case when k.question ~ 'خشک' then 'خشک' when k.question ~ 'چرب' then 'چرب' end
from public.knowledge k
where k.category = 'محصول' and k.question ~ '^قیمت و مشخصات' and k.url is not null
on conflict (url) do nothing;

-- which ingredient appears in which single product (matched in the owner's own bullet lists)
insert into public.product_active (url, ingredient_id, role_text)
select p.url, i.id,
       (select btrim(substr(l, 3))
          from public.knowledge k2, unnest(string_to_array(k2.answer, E'\n')) l
         where k2.url = p.url and k2.category = 'محصول' and l like '• %'
           and exists (select 1 from unnest(i.aliases) a where position(private.normalize_fa(a) in private.normalize_fa(l)) > 0)
         order by (l like '%:%' or l like '%؛%') desc, length(l) desc
         limit 1)
from public.product_info p
join public.active_ingredient i
  on exists (
       select 1
       from public.knowledge k, unnest(string_to_array(k.answer, E'\n')) l, unnest(i.aliases) a
       where k.url = p.url and k.category = 'محصول' and l like '• %'
         and position(private.normalize_fa(a) in private.normalize_fa(l)) > 0)
where p.kind = 'single'
on conflict do nothing;
