"""Convert a WordPress/WooCommerce export (WXR .xml) into knowledge rows (JSON) for Supabase.

usage: python3 tools/wp_to_knowledge.py export.xml data/knowledge.json

Only PUBLISHED products, posts and pages are used. Coupons, users, comments, drafts and media are ignored.
Prices are read as-is from the export (Toman) and are a snapshot: re-export and re-run to refresh.
"""
import sys, re, json, html
from html.parser import HTMLParser

import xml.etree.ElementTree as ET

NS = {"wp": "http://wordpress.org/export/1.2/", "content": "http://purl.org/rss/1.0/modules/content/"}


def load_rows(path):
    ch = ET.parse(path).getroot().find("channel")
    out = []
    for it in ch.findall("item"):
        pt = it.findtext("wp:post_type", namespaces=NS)
        st = it.findtext("wp:status", namespaces=NS)
        if st != "publish" or pt not in ("product", "page", "post"):
            continue
        cats = [c.text for c in it.findall("category")
                if c.get("domain") in ("category", "product_cat", "post_tag", "product_tag") and c.text]
        price = next((m.findtext("wp:meta_value", namespaces=NS) for m in it.findall("wp:postmeta", NS)
                      if m.findtext("wp:meta_key", namespaces=NS) == "_price"), None)
        out.append(dict(type=pt, title=it.findtext("title"), link=it.findtext("link"),
                        slug=it.findtext("wp:post_name", namespaces=NS),
                        html=it.findtext("content:encoded", default="", namespaces=NS), cats=cats, price=price))
    return out


rows = load_rows(sys.argv[1])

MAXC = 1100


class P(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.items = []      # ('h', level, text) | ('p', text)
        self.buf = []
        self.in_h = None
        self.skip = 0
        self.li = False

    def flush(self):
        t = re.sub(r"\s+", " ", "".join(self.buf)).strip()
        self.buf = []
        return t

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style"):
            self.skip += 1
        elif re.fullmatch(r"h[1-6]", tag) or tag == "summary":
            t = self.flush()
            if t:
                self.items.append(("p", t))
            self.in_h = int(tag[1]) if tag != "summary" else 3
        elif tag == "li":
            t = self.flush()
            if t:
                self.items.append(("p", t))
            self.li = True
        elif tag == "br":
            t = self.flush()
            if t:
                self.items.append(("p", t))

    def handle_endtag(self, tag):
        if tag in ("script", "style"):
            self.skip = max(0, self.skip - 1)
        elif re.fullmatch(r"h[1-6]", tag) or tag == "summary":
            t = self.flush()
            if t:
                self.items.append(("h", self.in_h, t))
            self.in_h = None
        elif tag in ("p", "li", "div", "tr", "td", "ul", "ol", "table", "section", "blockquote", "details"):
            t = self.flush()
            if t:
                self.items.append(("p", ("• " + t) if (tag == "li" or self.li) and tag == "li" else t))
            if tag == "li":
                self.li = False

    def handle_data(self, data):
        if not self.skip:
            self.buf.append(data)


def parse(h):
    h = re.sub(r"<!--.*?-->", " ", h or "", flags=re.S)
    p = P()
    p.feed(h)
    t = p.flush()
    if t:
        p.items.append(("p", t))
    return p.items


BOILER = re.compile(r"(را نیز مطالعه کنید|پیشنهاد می.?کنیم صفحه|برای مشاهده .* کلیک)")


def split_text(text, limit=MAXC):
    """split long text at paragraph, then sentence boundaries."""
    parts, cur = [], ""
    for para in text.split("\n"):
        if len(para) > limit:
            sents = re.split(r"(?<=[\.\!\?؟])\s+", para)
        else:
            sents = [para]
        for s in sents:
            if cur and len(cur) + len(s) + 1 > limit:
                parts.append(cur.strip())
                cur = s
            else:
                cur = (cur + "\n" + s) if cur else s
    if cur.strip():
        parts.append(cur.strip())
    return parts


def short(s, n):
    s = s.strip()
    return s if len(s) <= n else s[: n - 1].rstrip() + "…"


def q_for(heading, title):
    h = heading.strip().rstrip(":")
    if len(h.split()) < 4 and title and title not in h:
        h = f"{h} ({title})"
    return short(h, 300)


out = []
seen = set()


def add(q, a, kw, cat, url):
    a = a.strip()
    if len(q) < 3 or len(a) < 20:
        return
    key = (q, a)
    if key in seen:
        return
    seen.add(key)
    out.append(dict(question=short(q, 300), answer=a[:4000], keywords=short(kw, 500) if kw else None,
                    category=cat, url=url))


def toman(p):
    if not (p and str(p).isdigit()):
        return None
    return f"{int(p):,}".replace(",", "٬").translate(str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹"))


def faq_q(q, title):
    q = q.strip()
    if re.match(r"^(به طور کلی|در نهایت|نتیجه|جمع.?بندی)", q):
        return short(f"جمع‌بندی: {title}", 300)
    return q_for(q, title) if "؟" not in q else short(q, 300)


def sections(items):
    """-> intro_items, [ (h2_text, [items]) ]"""
    intro, secs, cur = [], [], None
    for it in items:
        if it[0] == "h" and it[1] <= 2:
            cur = (it[2], [])
            secs.append(cur)
        elif cur is None:
            intro.append(it)
        else:
            cur[1].append(it)
    return intro, secs


def render(items):
    lines = []
    for it in items:
        if it[0] == "h":
            lines.append(it[2].rstrip(":") + ":")
        else:
            if BOILER.search(it[1]):
                continue
            lines.append(it[1])
    return "\n".join(lines).strip()


def ingest_doc(r, cat, intro_q):
    title = (r["title"] or "").strip()
    url = r["link"]
    cats = [c for c in r["cats"] if c and "بندی نشده" not in c]
    kw = " ".join([title] + cats)
    items = parse(r["html"])
    intro, secs = sections(items)
    t = render(intro)
    if t:
        for i, part in enumerate(split_text(t)):
            add(intro_q if i == 0 else f"{intro_q} (ادامه {i})", part, kw, cat, url)
    for h2, its in secs:
        if re.search(r"س[وؤ]الات متداول", h2):
            # each h3 is its own Q&A
            q, buf = None, []
            for it in its:
                if it[0] == "h":
                    if q and buf:
                        add(faq_q(q, title), render([("p", x) for x in buf]), kw, cat, url)
                    q, buf = it[2], []
                elif q:
                    buf.append(it[1])
            if q and buf:
                add(faq_q(q, title), render([("p", x) for x in buf]), kw, cat, url)
            continue
        text = render(its)
        if not text:
            continue
        q0 = q_for(h2, title)
        for i, part in enumerate(split_text(text)):
            add(q0 if i == 0 else short(f"{q0} (ادامه {i})", 300), part, kw, cat, url)


# --- products
for r in rows:
    if r["type"] != "product":
        continue
    title = r["title"].strip()
    url = r["link"]
    price = toman(r["price"])
    cats = " ".join(c for c in r["cats"] if "بندی نشده" not in c)
    a = f"{title}\n"
    if price:
        a += f"قیمت: {price} تومان\n"
    if cats:
        a += f"دسته‌بندی: {cats}\n"
    a += "برای قیمت و تخفیف به‌روز و خرید، صفحه‌ی محصول را ببینید."
    add(f"قیمت و مشخصات {title}", a, f"قیمت خرید چنده هزینه سفارش {title} {cats}", "محصول", url)
    ingest_doc(r, "محصول", f"معرفی {title}")

# --- posts: published only; drop the shorter duplicate title
posts = [r for r in rows if r["type"] == "post"]
by_title = {}
for r in posts:
    k = (r["title"] or "").strip()
    if k not in by_title or len(r["html"]) > len(by_title[k]["html"]):
        by_title[k] = r
for r in by_title.values():
    ingest_doc(r, "مقاله", (r["title"] or "").strip())

# --- pages
for r in rows:
    if r["type"] != "page":
        continue
    if r["title"] == "سوالات متداول":
        ingest_doc(dict(r, cats=["سوالات متداول زویتر"]), "سؤالات متداول", "سوالات متداول زویتر")
    elif r["title"] == "درباره ما":
        lines = [x[1] for x in parse(r["html"]) if x[0] == "p" and len(x[1]) > 120]
        if lines:
            add("درباره‌ی برند زویتر چیست؟ شرکت سازنده کیست؟", lines[0], "درباره زویتر زینوتابان یگانه برند سازنده شرکت", "درباره‌ی ما", r["link"])
    elif r["title"] == "تماس با ما":
        add("شماره تماس، آدرس و ایمیل زویتر چیست؟",
            "آدرس دفتر: تهران، تهرانپارس، فرجام شرقی پلاک ۶۱ واحد ۱۴\nشماره تماس: 09031464741\nایمیل: info@zuyter.com",
            "تماس با ما آدرس تلفن شماره پشتیبانی ایمیل دفتر", "درباره‌ی ما", r["link"])

# Owner-curated synonyms: customers say "مرجوعی", the site says "بازگشت کالا".
SYNONYMS = {
    "آیا محصولات زویتر اصل": "اصالت اورجینال تقلبی اصل بودن مجوز وزارت بهداشت سازمان غذا و دارو",
    "محصولات زویتر تا چه مدت ضمانت": "مرجوعی مرجوع عودت برگشت کالا بازگرداندن تعویض ضمانت",
    "چطور می": "تخفیف کد تخفیف جشنواره حراج خبرنامه",
    "شماره تماس، آدرس": "تلفن موبایل واتساپ آدرس ایمیل پشتیبانی تماس دفتر",
}
for row in out:
    for prefix, syn in SYNONYMS.items():
        if row["question"].startswith(prefix) and row["category"] in ("سؤالات متداول", "درباره‌ی ما"):
            row["keywords"] = short(((row["keywords"] + " ") if row["keywords"] else "") + syn, 500)

json.dump(out, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
from collections import Counter

c = Counter(x["category"] for x in out)
print("rows:", len(out), dict(c))
L = [len(x["answer"]) for x in out]
print("answer chars: min", min(L), "avg", sum(L) // len(L), "max", max(L), "| total", sum(L), "| bytes≈", sum(len((x['question'] + x['answer'] + (x['keywords'] or '')).encode()) for x in out))
print("too long q:", sum(len(x["question"]) > 300 for x in out), "| kw>500:", sum(len(x["keywords"] or "") > 500 for x in out))
