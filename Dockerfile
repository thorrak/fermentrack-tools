
FROM jdbeeler/fermentrack:latest

ENV PYTHONUNBUFFERED 1

COPY --chown=django:django ./envs/django /app/.envs/.production/.django
COPY --chown=django:django ./envs/postgres /app/.envs/.production/.postgres

# Correct the permissions for /app/data and /app/log
RUN chown django /app/data/
RUN chown django /app/log/

USER django

WORKDIR /app

ENTRYPOINT ["/entrypoint"]