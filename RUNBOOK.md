# FortySeal — Runbook Incident Response
> **NIS2 Art. 21 / GDPR Art. 33** — Documento obbligatorio per gestione incidenti di sicurezza.
> Aggiornare ad ogni nuovo deployment. Versione: 1.0 — Maggio 2026

---

## 1. Contatti di Emergenza

| Ruolo | Nome | Canale |
|---|---|---|
| Responsabile tecnico | Admin FortySeal | sealforty@gmail.com |
| Data Protection Officer | Da nominare | — |
| Hosting (Render) | Support | https://render.com/support |

---

## 2. Classificazione Incidenti

| Livello | Definizione | Esempio | Tempo risposta |
|---|---|---|---|
| **P1 — CRITICO** | Servizio completamente down o breach dati confermato | DB inaccessibile, leak PII | < 30 minuti |
| **P2 — ALTO** | Funzionalità core degradata o tentativo breach | Circuit breaker OPEN, brute-force rilevato | < 2 ore |
| **P3 — MEDIO** | Funzionalità non-core degradata | Email non inviate, Telegram bot down | < 8 ore |
| **P4 — BASSO** | Anomalia non impattante | Log insoliti, latenza alta | < 48 ore |

---

## 3. Procedure per Tipo di Incidente

### 3.1 Breach di Dati / Accesso Non Autorizzato

**Sintomi:** Login anomali, accessi da IP insoliti, `AuditLog` con severity CRITICAL

**Procedura:**
```bash
# 1. Identificare sessioni attive sospette
# Django admin → Sessions → filtrare per data/IP
# Oppure: /security-alerts/ per vedere IP sospetti

# 2. Terminare sessioni compromesse
python manage.py shell -c "
from django.contrib.sessions.models import Session
from django.utils import timezone
# Eliminare tutte le sessioni (logout forzato globale)
Session.objects.filter(expire_date__gte=timezone.now()).delete()
print('Sessioni terminate')
"

# 3. Bloccare utente sospetto
python manage.py shell -c "
from django.contrib.auth.models import User
u = User.objects.get(username='USERNAME_SOSPETTO')
u.is_active = False
u.save()
print('Utente disabilitato')
"

# 4. Raccogliere evidence (NON modificare i log)
cp logs/app.jsonl /tmp/incident_$(date +%Y%m%d_%H%M%S).jsonl
cp logs/errors.jsonl /tmp/incident_errors_$(date +%Y%m%d_%H%M%S).jsonl
```

**Notifica GDPR Art. 33:** Se i dati violati riguardano persone fisiche UE, notificare il Garante entro **72 ore** dalla scoperta.
→ Form: https://www.garanteprivacy.it/notifica-data-breach

---

### 3.2 Servizio Down (503 / DB irraggiungibile)

**Sintomi:** `/health/` restituisce 503, errori su Sentry/email ADMINS

**Procedura:**
```bash
# 1. Verificare stato componenti
curl https://fortyseal-1.onrender.com/health/
# Risposta attesa: {"status": "ok", "checks": {...}, "elapsed_ms": N}

# 2. Verificare DB (PostgreSQL)
# Render dashboard → Database → Connections / Logs

# 3. Restart servizio su Render
# Dashboard Render → Manual Deploy → oppure push commit vuoto:
git commit --allow-empty -m "chore: trigger restart"
git push origin main

# 4. Verificare circuit breakers
# /superuser/circuit-breakers/ — resettare manualmente se necessario

# 5. Rollback se deploy problematico
# Render → Deploys → selezionare deploy precedente → "Rollback to this deploy"
```

---

### 3.3 Brute-Force / Attacco DDoS

**Sintomi:** Molti 401/403 in `logs/errors.jsonl`, IP bloccati in `IPSecurityMiddleware`

**Procedura:**
```bash
# 1. Identificare IP attaccante
cat logs/app.jsonl | python -c "
import sys, json
from collections import Counter
ips = []
for line in sys.stdin:
    try:
        e = json.loads(line)
        if 'ip' in e: ips.append(e['ip'])
    except: pass
print(Counter(ips).most_common(10))
"

# 2. Verificare IP già bloccati
# /security-alerts/ → sezione IP Sospetti

# 3. Aggiungere IP a blocklist permanente (se necessario)
python manage.py shell -c "
from Cripto1.models import BlockedIP
BlockedIP.objects.create(ip_address='IP_ATTACCANTE', reason='Brute-force manuale')
"

# 4. Se attacco massiccio: attivare WAF Render o Cloudflare (piano a pagamento)
```

---

### 3.4 Telegram Bot Down

**Sintomi:** Circuit breaker `telegram` in stato OPEN, transazioni bot non create

**Procedura:**
```bash
# 1. Verificare stato bot
curl https://api.telegram.org/bot<TOKEN>/getMe

# 2. Reset circuit breaker
# /superuser/circuit-breakers/ → TELEGRAM → Reset (→ CLOSED)

# 3. Verificare token nel .env
grep TELEGRAM_BOT_TOKEN Cripto/.env

# 4. Riavviare bot worker se necessario
# Render → Bot service → Manual restart
```

---

### 3.5 Email Non Inviate

**Sintomi:** Circuit breaker `smtp` in OPEN, utenti non ricevono email

**Procedura:**
```bash
# 1. Testare SMTP manualmente
python manage.py shell -c "
from django.core.mail import send_mail
send_mail('Test', 'Test body', 'sealforty@gmail.com', ['sealforty@gmail.com'])
"

# 2. Verificare credenziali Gmail
# sealforty@gmail.com → Account Google → Sicurezza → App password

# 3. Reset circuit breaker SMTP
# /superuser/circuit-breakers/ → SMTP → Reset (→ CLOSED)

# 4. Alternativa temporanea: inviare email manualmente dagli AuditLog
```

---

## 4. Deployment Zero-Downtime su Render

### Pre-deploy checklist
```bash
# 1. Aggiornare requirements.lock
pip-compile --generate-hashes --allow-unsafe -o requirements.lock requirements.in

# 2. Eseguire migrazioni in staging prima
python manage.py migrate --check  # verifica migrazioni pendenti senza applicarle

# 3. Verificare che le migrazioni siano backward-compatible
# (non eliminare colonne/tabelle usate dalla versione precedente)

# 4. Test locale
python manage.py check --deploy
python manage.py test Cripto1 --keepdb
```

### Deploy
```bash
# Render esegue automaticamente:
# 1. pip install -r requirements.txt
# 2. python manage.py migrate
# 3. python manage.py collectstatic --noinput
# 4. Restart graceful (gunicorn --graceful-timeout 30)

# Per deploy manuale:
git push origin main
# Oppure: Render Dashboard → Manual Deploy
```

### Post-deploy verifica
```bash
# 1. Health check
curl https://fortyseal-1.onrender.com/health/

# 2. Smoke test manuale: login, transazione, documento

# 3. Monitorare Sentry per 15 minuti dopo il deploy

# 4. Se problemi: Rollback immediato da Render Dashboard
```

---

## 5. Backup e Ripristino DB

```bash
# Backup manuale PostgreSQL (da Render → Database → Backups)
# Oppure via management command:
python manage.py backup_blockchain  # salva snapshot blockchain

# Ripristino
# Render → Database → Point-in-time recovery
# ATTENZIONE: notificare utenti prima del ripristino (potenziale perdita dati)
```

---

## 6. Notifica Breach GDPR (Art. 33) — Checklist 72h

- [ ] **Ora scoperta breach:** ___________
- [ ] **Deadline notifica Garante:** ___________ (+ 72h)
- [ ] Dati coinvolti identificati (quali categorie, quanti interessati)
- [ ] Sessioni compromesse terminate
- [ ] Password utenti coinvolti resettate
- [ ] Log di evidence conservati e non modificati
- [ ] Form Garante compilato: https://www.garanteprivacy.it/notifica-data-breach
- [ ] Utenti coinvolti notificati (Art. 34 — se rischio elevato)
- [ ] Incident post-mortem documentato

---

## 7. Log di Incidenti Passati

| Data | Tipo | Risoluzione | Durata |
|---|---|---|---|
| — | — | — | — |

*Aggiornare questa tabella ad ogni incidente risolto.*
