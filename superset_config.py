import os

SECRET_KEY = os.environ.get("SUPERSET_SECRET_KEY", "change-me-demo-secret-key-please-rotate")
SQLALCHEMY_DATABASE_URI = "postgresql+psycopg2://postgres:postgres@db:5432/superset"

BABEL_DEFAULT_LOCALE = "fa"
LANGUAGES = {
    "fa": {"flag": "ir", "name": "فارسی"},
    "en": {"flag": "us", "name": "English"},
}

# Jinja in dataset SQL is what expands the Jalali macros.
FEATURE_FLAGS = {"ENABLE_TEMPLATE_PROCESSING": True}

from superset_jalali_sql import JINJA_ADDONS

JINJA_CONTEXT_ADDONS = dict(JINJA_ADDONS)
# 1390–1420 is enough for this demo and keeps the calendar join small.
# The library itself supports 1350–1550.
JALALI_SQL = {"dialect": "postgresql", "digits": "latin", "min_year": 1390, "max_year": 1420}
