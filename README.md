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

`nowruz.py` stores the Gregorian date of Nowruz for each year from 1350 to 1550. `jalali_join` turns that table into a `VALUES` list and left-joins it so:

```text
sale_date >= start_date AND sale_date < next_start_date
```

`jalali_columns` counts the days since that Nowruz. The first six months are 31 days (186 days). The next five are 30. Esfand is whatever remains until the next Nowruz, 29 or 30. A NULL date, or a date outside the configured years, leaves every Jalali column NULL and keeps the sales row.

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
