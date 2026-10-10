-- Superset metadata database, plus a small sales table whose dates stay Gregorian.
CREATE DATABASE superset;
CREATE DATABASE demo;
\connect demo

SELECT setseed(0.42);

CREATE TABLE sales (
  id bigserial PRIMARY KEY,
  sale_date date NOT NULL,
  category text NOT NULL,
  amount numeric(14, 0) NOT NULL
);

-- One Jalali year: Nowruz 1403 through the day before Nowruz 1404.
INSERT INTO sales (sale_date, category, amount)
SELECT d::date,
       (ARRAY['پوشاک', 'مواد غذایی', 'دیجیتال'])[1 + floor(random() * 3)::int],
       round((random() * 90 + 10) * 100000)
FROM generate_series(DATE '2024-03-20', DATE '2025-03-19', INTERVAL '1 day') AS d
CROSS JOIN generate_series(1, 4) AS g;

CREATE INDEX ON sales (sale_date);

CREATE ROLE demo_reader LOGIN PASSWORD 'demo_reader';
GRANT CONNECT ON DATABASE demo TO demo_reader;
GRANT USAGE ON SCHEMA public TO demo_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO demo_reader;
