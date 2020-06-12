#!/bin/bash
export DB_HOST=${DB_HOST:-db}
export DB_PORT=${DB_PORT:-5432}
export RABBITMQ_HOST=${RABBITMQ_HOST:-rabbitmq}
export RABBITMQ_PORT=${RABBITMQ_PORT:-5672}

echo "[+] Wait for DB availability"
while !</dev/tcp/$DB_HOST/$DB_PORT; do sleep 1; done

echo "[+] Wait for RabbitMQ availability"
while !</dev/tcp/$RABBITMQ_HOST/$RABBITMQ_PORT; do sleep 1; done

source env3/bin/activate

# Apply database migrations
# echo "[+] Make database migrations (events)"
# python manage.py makemigrations events
#
# echo "[+] Apply database migrations (events --fake)"
# python manage.py migrate --fake

echo "[+] Make database migrations"
echo " - scans"
python manage.py makemigrations scans
echo " - findings"
python manage.py makemigrations findings
echo " - events"
python manage.py makemigrations events
echo " - ... and all the rest"
python manage.py makemigrations

# Apply database migrations
echo "[+] Apply database migrations"
python manage.py migrate

# Check for first install
if [ ! -f status.created ]; then
  # Create the default admin user
  echo "[+] Create the default admin user (if needeed)"
  # Be careful with Python identation and echo command
  echo -e "\r\
from django.contrib.auth import get_user_model\r\
User = get_user_model()\r\
if not User.objects.filter(username='admin').exists(): \r\
  User.objects.create_superuser('admin', 'admin@dev.patrowl.io', 'Bonjour1!')" | python manage.py shell

  # Populate the db with default data
  echo "[+] Populate the db with default data"
  python manage.py loaddata var/data/assets.AssetCategory.json
  python manage.py loaddata var/data/engines.Engine.json
  python manage.py loaddata var/data/engines.EnginePolicyScope.json
  python manage.py loaddata var/data/engines.EnginePolicy.json

  touch status.created
fi

# Start Supervisord (Celery workers)
echo "[+] Start Supervisord (Celery workers)"
supervisord -c var/etc/supervisord.conf

# Configure engines and turn-on auto-refresh engine status
if [ -f set_engines.py ]; then
  python manage.py shell < set_engines.py
fi

# Start server
echo "[+] Starting server"
gunicorn -b 0.0.0.0:8003 app.wsgi:application --timeout 300
