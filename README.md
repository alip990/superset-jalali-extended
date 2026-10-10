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
