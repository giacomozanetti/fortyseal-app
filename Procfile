web: gunicorn Cripto.wsgi:application --bind 0.0.0.0:$PORT --workers 4 --timeout 120 --log-file - --access-logfile - --error-logfile -
worker: python manage.py run_telegram_bot
celeryworker: celery -A Cripto worker -l info --concurrency=2
celerybeat: celery -A Cripto beat -l info
