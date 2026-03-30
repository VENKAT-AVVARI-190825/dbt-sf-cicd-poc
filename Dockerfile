FROM python:3.11-slim

RUN pip install --no-cache-dir dbt-snowflake snowflake-cli

WORKDIR /app
COPY media_dataops/ ./media_dataops/
COPY entrypoint.sh ./entrypoint.sh
RUN chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]
