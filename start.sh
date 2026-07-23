#!/usr/bin/env bash
set -e

# =============================================================================
# start.sh — entrypoint del container FortySeal (Docker Compose e Render/Docker)
#
# Al PRIMO avvio (e in modo idempotente ai successivi) esegue il bootstrap
# completo dell'applicazione, equivalente ai passi manuali di Procedura.md:
#   1. makemigrations Cripto1 + storage_gateway   (crea le migrazioni mancanti)
#   2. migrate                                     (applica lo schema al DB)
#   3. setup permessi / ruoli / organizzazioni     (comandi idempotenti)
#   4. collectstatic
#   5. avvio gunicorn
#
# I comandi di bootstrap (passo 3) sono idempotenti e tolleranti agli errori:
# un fallimento logga un warning ma NON impedisce l'avvio del web server.
# migrate/makemigrations invece sono critici (set -e): se falliscono il boot
# si ferma, perché lo schema del DB deve essere coerente.
# =============================================================================

echo "==> [1/5] Generazione migrazioni (makemigrations)..."
python manage.py makemigrations Cripto1 --noinput
python manage.py makemigrations storage_gateway --noinput

echo "==> [2/5] Applicazione migrazioni (migrate)..."
python manage.py migrate --noinput

echo "==> [3/5] Bootstrap permessi / ruoli / organizzazioni (idempotente)..."
python manage.py setup_permissions --force            || echo "   [warn] setup_permissions non completato"
python manage.py create_pqc_role                      || echo "   [warn] create_pqc_role non completato"
python manage.py create_org_admin_permissions         || echo "   [warn] create_org_admin_permissions non completato"
python manage.py create_org_admin_role                || echo "   [warn] create_org_admin_role non completato"
python manage.py setup_organizations                  || echo "   [warn] setup_organizations non completato"
python manage.py setup_organizations --create-default || echo "   [warn] setup_organizations --create-default non completato"

echo "==> [4/5] Collectstatic..."
python manage.py collectstatic --noinput

echo "==> [5/5] Avvio gunicorn..."
exec gunicorn Cripto.wsgi:application \
    --bind 0.0.0.0:10000 \
    --workers 2 \
    --timeout 120
