# Superset Jalali

Apache Superset 6.1 with Shamsi (Jalali) dates. The business table keeps a normal Gregorian `sale_date`. Year, month, day, season, and weekday are calculated in the query. Nothing is installed in PostgreSQL: no calendar extension, no stored function, no extra column on `sales`.

## Start

```bash
docker compose up --build -d
docker compose logs -f superset-init
```

Wait until `superset-init` exits successfully, then open:

| | |
|---|---|
| Superset | http://localhost:8088 |
| Login | `admin` / `admin` |
| Postgres | `127.0.0.1:5442` (`postgres` / `postgres`, database `demo`) |

If port 8088 is already taken, start with another host port:

```bash
SUPERSET_PORT=8099 docker compose up --build -d
```

Stop and keep the data with `docker compose down`. `docker compose down -v` also deletes the Postgres volume, so the sample sales rows are loaded again on the next start.

## Connect the sample data

In Superset: **Settings → Database Connections → + Database → PostgreSQL**.

```text
postgresql+psycopg2://demo_reader:demo_reader@db:5432/demo
```

`db` is the Compose service name. Use it from inside Superset, not `localhost`.

## One virtual dataset

**Data → Datasets → + Dataset**, choose that database, and use SQL Lab or a virtual dataset with:

```sql
SELECT s.*, {{ jalali_columns('s.sale_date') }}
FROM sales s
{{ jalali_join('s.sale_date') }}
```

Save it as `sales_jalali`. Superset runs the Jinja macros while it reads the columns, so the dataset shows real fields such as `jalali_year` and `jalali_month_label`.

Then create a chart from `sales_jalali`. Use a Jalali column as the dimension (for example `jalali_month_label` on a bar chart, metric `SUM(amount)`). Superset’s own time grain stays Gregorian; these columns are categories.

The sample rows cover Nowruz 1403 through the day before Nowruz 1404 (`2024-03-20` .. `2025-03-19`).

## Columns

| Column | Meaning |
|---|---|
| `jalali_year` | Year, integer |
| `jalali_month_num` | Month number, 1–12 |
| `jalali_day` | Day of month |
| `jalali_date` | Sortable text, `1403/07/18` |
| `jalali_date_int` | Numeric key, `14030718` |
| `jalali_month` | `1403-07` |
| `jalali_month_name` | Persian month name |
| `jalali_month_label` | `1403-07 مهر` |
| `jalali_season` | Persian season name |
| `jalali_season_key` | `1403-3 پاییز` |
| `jalali_weekday` | Persian weekday |
| `jalali_weekday_num` | Saturday = 0, Friday = 6 |
| `jalali_week_start` | Gregorian date of that Saturday |

A numeric range on `jalali_date_int` is a Shamsi from/to. `14030701`–`14030730` is 1–30 Mehr 1403, the same window as:

```sql
sale_date >= DATE '2024-09-22' AND sale_date < DATE '2024-10-22'
```

## How a date becomes Jalali

`nowruz.py` stores the Gregorian date of Nowruz for each year from 1350 to 1550. `jalali_join('s.sale_date')` does not convert the day. It only attaches the Shamsi year that contains that Gregorian date.

Superset replaces the macro with a `LEFT JOIN` against a `VALUES` list. In this demo the list is years 1390–1420. Each row is the year, Nowruz of that year, and Nowruz of the next year:

```sql
LEFT JOIN (VALUES
  (1403, DATE '2024-03-20', DATE '2025-03-21'),
  (1404, DATE '2025-03-21', DATE '2026-03-21')
) AS _jy(jy, start_date, next_start_date)
  ON CAST(s.sale_date AS DATE) >= _jy.start_date
 AND CAST(s.sale_date AS DATE) <  _jy.next_start_date
```

`2024-09-22` is on or after Nowruz 1403 and before Nowruz 1404, so `_jy.jy` is 1403. A NULL date, or a date outside the configured years, stays in the result with `_jy.jy` NULL.

## How each column is generated

`jalali_columns` counts the days from that Nowruz. Call that count `doy`. 1 Farvardin is `doy = 0`.

The first six months are 31 days, 186 days in total. Mehr through Bahman are 30 days each. Esfand runs until the next Nowruz (29 or 30 days).

```text
month = doy < 186 ? doy / 31 + 1        : (doy - 186) / 30 + 7
day   = doy < 186 ? doy % 31 + 1        : (doy - 186) % 30 + 1
season = (month - 1) / 3 + 1            -- 1 بهار, 2 تابستان, 3 پاییز, 4 زمستان
weekday = (EXTRACT(DOW FROM sale_date) + 1) % 7
```

PostgreSQL numbers Sunday as 0. Adding 1 and wrapping makes Saturday 0, so the names line up as شنبه … جمعه.

Every column below is wrapped as `CASE WHEN _jy.jy IS NULL THEN NULL ELSE <expr> END`. Integer division is the PostgreSQL `/` on these values.

| Column | Expression |
|---|---|
| `jalali_year` | `_jy.jy` |
| `jalali_month_num` | `month` |
| `jalali_day` | `day` |
| `jalali_date` | `year \|\| '/' \|\| lpad(month) \|\| '/' \|\| lpad(day)` → `1403/07/18` |
| `jalali_date_int` | `year * 10000 + month * 100 + day` → `14030718` |
| `jalali_month` | `year \|\| '-' \|\| lpad(month)` → `1403-07` |
| `jalali_month_name` | `CASE month WHEN 1 THEN 'فروردین' … WHEN 12 THEN 'اسفند' END` |
| `jalali_month_label` | `jalali_month \|\| ' ' \|\| jalali_month_name` → `1403-07 مهر` |
| `jalali_season` | `CASE season WHEN 1 THEN 'بهار' … WHEN 4 THEN 'زمستان' END` |
| `jalali_season_key` | `year \|\| '-' \|\| season \|\| ' ' \|\| season name` → `1403-3 پاییز` |
| `jalali_weekday` | `CASE weekday WHEN 0 THEN 'شنبه' … WHEN 6 THEN 'جمعه' END` |
| `jalali_weekday_num` | `weekday` |
| `jalali_week_start` | `sale_date - weekday`, the Gregorian Saturday of that week |

`lpad` writes the month and day as two digits. With `digits: latin` (this demo) the text stays `0-9`, so filters sort in calendar order. `digits='persian'` runs `TRANSLATE` on the text columns only (`jalali_date`, `jalali_month`, `jalali_month_name`, `jalali_month_label`, `jalali_season`, `jalali_season_key`, `jalali_weekday`). The numeric columns stay Latin so they remain numbers.

This demo narrows the join to 1390–1420 in `superset_config.py` (`JALALI_SQL`). Results inside that span match the full 1350–1550 table. Widen `min_year` / `max_year` there if you need more; both ends must stay inside 1350–1550.

Digits in the text columns are Latin (`digits: latin`) so filters sort cleanly. `digits='persian'` on `jalali_columns` rewrites the text columns only.

The anchors were generated so they agree with jdatetime 6.1.0 and persiantools 4.0.0. Regenerate with:

```bash
python3 -m venv .venv
.venv/bin/pip install -e 'packages[dev]'
.venv/bin/python packages/scripts/generate_nowruz.py
.venv/bin/pytest packages/tests
```

The Postgres test needs `JALALI_TEST_DSN` pointing at a database that already has `sales`.

## Layout

```text
Dockerfile              Superset 6.1.0, psycopg2, this package
superset_config.py      Persian UI, Jinja on, Jalali macros
docker-compose.yml      Postgres + Superset
db/01-init.sql          metadata DB, demo.sales, read-only role
packages/               superset-jalali-sql
```

Demo passwords are fixed on purpose. Change `SUPERSET_SECRET_KEY` and the database passwords before any shared deployment.

## فارسی

<div dir="rtl" lang="fa">

<h2>سوپرست با تاریخ شمسی</h2>

<p>جدول فروش فقط <code dir="ltr">sale_date</code> میلادی دارد. سال، ماه، روز، فصل و روز هفته هنگام اجرای کوئری ساخته می‌شوند. در PostgreSQL نه افزونهٔ تقویم نصب می‌شود، نه تابع ذخیره‌شده، نه ستون اضافه روی <code dir="ltr">sales</code>.</p>

<h3>اجرا</h3>

<pre dir="ltr"><code>docker compose up --build -d</code></pre>

<p>بعد از تمام شدن <code dir="ltr">superset-init</code>، سوپرست روی <code dir="ltr">http://localhost:8088</code> است. ورود: <code dir="ltr">admin</code> / <code dir="ltr">admin</code>. اگر پورت ۸۰۸۸ گرفته باشد:</p>

<pre dir="ltr"><code>SUPERSET_PORT=8099 docker compose up --build -d</code></pre>

<p>اتصال پایگاه نمونه، از داخل خود سوپرست (نه از <code dir="ltr">localhost</code>):</p>

<pre dir="ltr"><code>postgresql+psycopg2://demo_reader:demo_reader@db:5432/demo</code></pre>

<p>دیتاست مجازی را با این SQL بسازید و به نام <code dir="ltr">sales_jalali</code> ذخیره کنید:</p>

<pre dir="ltr"><code>SELECT s.*, {{ jalali_columns('s.sale_date') }}
FROM sales s
{{ jalali_join('s.sale_date') }}</code></pre>

<p>ردیف‌های نمونه از نوروز ۱۴۰۳ تا روز پیش از نوروز ۱۴۰۴ هستند (<code dir="ltr">2024-03-20</code> تا <code dir="ltr">2025-03-19</code>).</p>

<h3>کار <code dir="ltr">jalali_join</code></h3>

<p>این ماکرو خودِ روز را تبدیل نمی‌کند. فقط سال شمسیِ دربرگیرندهٔ تاریخ میلادی را به ردیف وصل می‌کند. سوپرست آن را به یک <code dir="ltr">LEFT JOIN</code> روی فهرست نوروز تبدیل می‌کند. در این دمو فهرست سال‌های ۱۳۹۰ تا ۱۴۲۰ است. هر ردیف سه مقدار دارد: شمارهٔ سال، تاریخ میلادی نوروز همان سال، و تاریخ میلادی نوروز سال بعد.</p>

<pre dir="ltr"><code>LEFT JOIN (VALUES
  (1403, DATE '2024-03-20', DATE '2025-03-21'),
  (1404, DATE '2025-03-21', DATE '2026-03-21')
) AS _jy(jy, start_date, next_start_date)
  ON CAST(s.sale_date AS DATE) &gt;= _jy.start_date
 AND CAST(s.sale_date AS DATE) &lt;  _jy.next_start_date</code></pre>

<p>تاریخ <code dir="ltr">2024-09-22</code> از نوروز ۱۴۰۳ گذشته و به نوروز ۱۴۰۴ نرسیده، پس <code dir="ltr">_jy.jy</code> برابر ۱۴۰۳ است. اگر تاریخ تهی باشد یا بیرون از بازهٔ تنظیم‌شده بیفتد، ردیف فروش می‌ماند و <code dir="ltr">_jy.jy</code> تهی است.</p>

<h3>ساخت هر ستون</h3>

<p><code dir="ltr">jalali_columns</code> تعداد روزهای گذشته از همان نوروز را می‌شمارد. این عدد را <code dir="ltr">doy</code> می‌نامیم. اول فروردین یعنی <code dir="ltr">doy = 0</code>.</p>

<p>شش ماه اول هر کدام ۳۱ روزند و روی هم ۱۸۶ روز. مهر تا بهمن هر کدام ۳۰ روز. اسفند تا نوروز بعد ادامه دارد و ۲۹ یا ۳۰ روز است.</p>

<pre dir="ltr"><code>month   = doy &lt; 186 ? doy / 31 + 1       : (doy - 186) / 30 + 7
day     = doy &lt; 186 ? doy % 31 + 1       : (doy - 186) % 30 + 1
season  = (month - 1) / 3 + 1
weekday = (EXTRACT(DOW FROM sale_date) + 1) % 7</code></pre>

<p>فصل ۱ بهار، ۲ تابستان، ۳ پاییز و ۴ زمستان است. PostgreSQL یکشنبه را ۰ می‌شمارد. با جمعِ یک و باقیمانده بر ۷، شنبه ۰ می‌شود و نام‌ها از شنبه تا جمعه ردیف می‌شوند.</p>

<p>همهٔ ستون‌های زیر داخل این قالب‌اند: اگر <code dir="ltr">_jy.jy</code> تهی باشد نتیجه تهی است، وگرنه عبارت ستون. تقسیم، تقسیم صحیح PostgreSQL است.</p>

<table>
<thead>
<tr><th>ستون</th><th>عبارت</th></tr>
</thead>
<tbody>
<tr><td dir="ltr"><code>jalali_year</code></td><td>خودِ <code dir="ltr">_jy.jy</code></td></tr>
<tr><td dir="ltr"><code>jalali_month_num</code></td><td>شمارهٔ ماه، همان <code dir="ltr">month</code></td></tr>
<tr><td dir="ltr"><code>jalali_day</code></td><td>روز ماه، همان <code dir="ltr">day</code></td></tr>
<tr><td dir="ltr"><code>jalali_date</code></td><td>سال و ماه و روز با خط کج و دو رقم، مثل <code dir="ltr">1403/07/18</code></td></tr>
<tr><td dir="ltr"><code>jalali_date_int</code></td><td><code dir="ltr">year * 10000 + month * 100 + day</code>، مثل <code dir="ltr">14030718</code></td></tr>
<tr><td dir="ltr"><code>jalali_month</code></td><td>سال و ماه با خط تیره، مثل <code dir="ltr">1403-07</code></td></tr>
<tr><td dir="ltr"><code>jalali_month_name</code></td><td>نام ماه با <code dir="ltr">CASE</code>، از فروردین تا اسفند</td></tr>
<tr><td dir="ltr"><code>jalali_month_label</code></td><td>ماه به‌اضافهٔ نام، مثل <code dir="ltr">1403-07 مهر</code></td></tr>
<tr><td dir="ltr"><code>jalali_season</code></td><td>نام فصل با <code dir="ltr">CASE</code></td></tr>
<tr><td dir="ltr"><code>jalali_season_key</code></td><td>سال، شمارهٔ فصل و نام، مثل <code dir="ltr">1403-3 پاییز</code></td></tr>
<tr><td dir="ltr"><code>jalali_weekday</code></td><td>نام روز هفته، شنبه تا جمعه</td></tr>
<tr><td dir="ltr"><code>jalali_weekday_num</code></td><td>شمارهٔ روز؛ شنبه ۰ و جمعه ۶</td></tr>
<tr><td dir="ltr"><code>jalali_week_start</code></td><td>تاریخ میلادی منهای شمارهٔ روز هفته، یعنی شنبهٔ همان هفته</td></tr>
</tbody>
</table>

<p>بازهٔ عددی روی <code dir="ltr">jalali_date_int</code> همان بازهٔ شمسی است. <code dir="ltr">14030701</code> تا <code dir="ltr">14030730</code> یعنی ۱ تا ۳۰ مهر ۱۴۰۳ و با این شرط میلادی یکی است: <code dir="ltr">sale_date &gt;= DATE '2024-09-22' AND sale_date &lt; DATE '2024-10-22'</code>.</p>

<p>در این دمو رقم‌های متنی لاتین می‌مانند (<code dir="ltr">digits: latin</code>) تا فیلتر به ترتیب تقویم مرتب شود. <code dir="ltr">digits='persian'</code> فقط ستون‌های متنی را به ارقام فارسی برمی‌گرداند. ستون‌های عددی لاتین می‌مانند تا نوع عددشان نشکند. بازهٔ سال در <code dir="ltr">superset_config.py</code> روی ۱۳۹۰ تا ۱۴۲۰ است. نتیجهٔ تاریخ‌های داخل این بازه با جدول کامل ۱۳۵۰ تا ۱۵۵۰ یکی است.</p>

</div>
