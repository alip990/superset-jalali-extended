FROM apache/superset:6.1.0
USER root
RUN uv pip install --python /app/.venv/bin/python --no-cache psycopg2-binary==2.9.13
COPY packages /tmp/superset-jalali-sql
RUN uv pip install --python /app/.venv/bin/python --no-cache /tmp/superset-jalali-sql && rm -rf /tmp/superset-jalali-sql
COPY superset_config.py /app/pythonpath/superset_config.py
ENV SUPERSET_CONFIG_PATH=/app/pythonpath/superset_config.py
USER superset
