# FortySeal — Post-Quantum Digital Trust Platform

> **FS-PQC-1.0** · Django 4.2 · liboqs · NIST FIPS 203/204/205 · Python 3.11

FortySeal is a production-grade **digital trust platform** that replaces classical cryptography with **NIST-standardised post-quantum algorithms** across every layer: transaction encryption, digital signatures, key lifecycle management, certificate revocation, and an internal integrity blockchain. It serves both **B2B organisations** (multi-tenant, role-based) and **B2C personal accounts** under a unified protocol labelled **FS-PQC-1.0**.

----

[![Security Audit — NIS2 Supply Chain](https://github.com/Aless1997/FortySeal/actions/workflows/security.yml/badge.svg)](https://github.com/Aless1997/FortySeal/actions/workflows/security.yml)
## Table of Contents


1. [Features](#features)
2. [PQC Architecture](#pqc-architecture)
3. [Tech Stack](#tech-stack)
4. [Project Structure](#project-structure)
5. [Setup — Local](#setup--local)
6. [Setup — Docker / Render](#setup--docker--render)
7. [Environment Variables](#environment-variables)
8. [Management Commands](#management-commands)
9. [API Overview](#api-overview)
10. [Use Cases](#use-cases)
11. [Security Model](#security-model)
12. [Roadmap](#roadmap)

---

## Features

| Area | Highlights |
|------|-----------|
| **Post-Quantum Cryptography** | ML-KEM-1024, ML-DSA-87, SLH-DSA-SHA2-256f, Falcon-1024 via **liboqs** (Open Quantum Safe) |
| **Transaction Engine** | Encrypted + PQC-signed transactions (text & files) with anti-replay tokens and unique message binding |
| **Key Management** | Per-user PQC key pairs, Argon2id-protected private keys, rotation, expiry, CRL |
| **Certificate Revocation (CRL)** | Server-side Dilithium-5-signed CRL snapshots, epoch-based propagation, fail-closed verification |
| **Internal Blockchain** | PoW-based append-only ledger with Merkle-root integrity, fork protection, and mining rate limits |
| **B2B Multi-tenancy** | Organisations, org admins, external API users, role-based permissions |
| **B2C Personal Accounts** | Plans with quotas, personal documents, community posts, PQC preferences |
| **API Suite** | External M2M API with PQC-signed request verification and key-pair ZIP export |
| **Telegram Bot** | Integrated bot for transaction management and notifications |
| **Browser Extension** | REST API + UI for browser-native PQC operations |
| **2FA** | TOTP (pyotp) with QR-code provisioning |
| **Real-time Chat** | Django Channels (WebSocket) |
| **Audit Log** | Append-only `AuditLog` with severity levels and structured JSON metadata |

---

## PQC Architecture

### Protocol: FS-PQC-1.0

All encrypted payloads produced by FortySeal carry the label `"proto": "FS-PQC-1.0"` and are structured as:

```
VERSION(1B) | HKDF-salt(16B) | KEM-ciphertext(1568B) | num_blocks(4B)
  [ block_len(4B) | ChaCha20-Poly1305(block) ] × N
```

Domain separation tag: `FS-PQC-TX-AAD`  
Nonce policy: `hkdf_derived_per_block` (no nonce reuse across blocks)

---

### Algorithms

| Role | Algorithm | NIST Standard | liboqs name | Key sizes |
|------|-----------|--------------|-------------|-----------|
| **Key Encapsulation (KEM)** | ML-KEM-1024 | FIPS 203 | `ML-KEM-1024` | PK 1568 B · CT 1568 B · SS 32 B |
| **Transaction / CRL Signing** | ML-DSA-87 (Dilithium-5) | FIPS 204 | `ML-DSA-87` | PK 2592 B · Sig 4595 B |
| **Optional Signing** | SLH-DSA-SHA2-256f | FIPS 205 | `SLH_DSA_PURE_SHA2_256F` | PK 64 B · Sig 49856 B |
| **API Suite Signing** | Falcon-1024 | — | `Falcon-1024` | PK 1793 B · Sig ~1280 B |

> All four algorithms are compiled from source via **liboqs** (Open Quantum Safe C library) and exposed through **liboqs-python**.

---

### Encryption Flow

```
plaintext
    │
    ▼
ML-KEM-1024 encap(recipient_PK) → (KEM_ciphertext, shared_secret)
    │
    ▼
HKDF-SHA256(shared_secret, salt) → master_key
    │
    ├─ HKDF(master_key, block_index) → block_key (32 B)
    └─ HKDF(master_key, block_index) → nonce     (12 B)
    │
    ▼
ChaCha20-Poly1305(block_key, nonce, plaintext_block, AAD)
```

Private keys are encrypted at rest with **AES-256-GCM** using a key derived via **Argon2id** (PBKDF2 fallback) from the user's password.

---

### Signature Verification with CRL

```
verify_signature(msg, sig, pk, alg)
    └─ OK? → check CRL (crl_manager.is_key_revoked(keypair_id))
                 └─ revoked? → REJECT + AuditLog(CRITICAL)
                 └─ clean?   → ACCEPT
```

Fail-closed: a CRL check error **rejects** the signature rather than silently accepting it.

---

## Tech Stack

| Component | Version / Notes |
|-----------|----------------|
| Python | 3.11 |
| Django | 4.2 – 5.2 |
| liboqs-python | 0.14.1 (liboqs C built from `main`) |
| cryptography | ≥ 41.0 (AES-256-GCM, HKDF, ChaCha20-Poly1305) |
| Django Channels | ≥ 4.0 (WebSocket / ASGI) |
| Gunicorn | ≥ 21.0 |
| Whitenoise | ≥ 6.5 |
| PostgreSQL | via psycopg2 / dj-database-url |
| Celery | ≥ 5.3 (async tasks) |
| Sentry | sentry-sdk[django] |
| python-telegram-bot | 21.9 |

---

## Project Structure

```
Cripto/                        ← repo root (Django project)
├── Dockerfile
├── requirements.txt
├── manage.py
├── Cripto/                    ← Django project package
│   ├── settings.py
│   ├── urls.py
│   ├── wsgi.py
│   └── asgi.py
└── Cripto1/                   ← main application
    ├── pqc_crypto.py          ← liboqs wrappers, FS-PQC-1.0 encryption/decryption
    ├── pqc_crl.py             ← CRL lifecycle (revocation, Dilithium-5 snapshots)
    ├── pqc_decryption_utils.py
    ├── crypto_utils.py        ← AES-256-GCM, PBKDF2, SecureBytes
    ├── blockchain_security.py ← PoW, Merkle, fork protection, mining limits
    ├── models.py              ← PQCKeyPair, Transaction, Block, AuditLog, …
    ├── views.py               ← B2B transaction/blockchain views
    ├── b2c_views.py           ← B2C personal account views
    ├── pqc_views.py           ← PQC dashboard, key management
    ├── api_suite_views.py     ← External M2M API
    ├── management/commands/   ← 30 management commands
    ├── telegram_bot/          ← Telegram bot runtime
    └── templates/
```

---

## Setup — Local

### Prerequisites

- Python 3.11
- PostgreSQL (or SQLite for development)
- MSYS2 / gcc on Windows **or** apt gcc on Linux (to compile liboqs)
- CMake ≥ 3.15, Ninja

### 1. Clone and create virtualenv

```bash
git clone <repo-url>
cd Cripto
python -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
```

### 2. Build and install liboqs C library

**Linux / macOS:**
```bash
sudo apt-get install -y cmake ninja-build gcc g++ libssl-dev  # Debian/Ubuntu
git clone --depth 1 --branch main https://github.com/open-quantum-safe/liboqs.git /tmp/liboqs
cmake -S /tmp/liboqs -B /tmp/liboqs/build \
    -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release \
    -DOQS_BUILD_ONLY_LIB=ON -DCMAKE_INSTALL_PREFIX=/usr/local -G Ninja
cmake --build /tmp/liboqs/build --parallel 4
sudo cmake --install /tmp/liboqs/build
sudo ldconfig
```

**Windows (MSYS2 UCRT64):**
```bash
pacman -S git mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja
git clone --depth 1 --branch main https://github.com/open-quantum-safe/liboqs.git /c/liboqs
cmake -S /c/liboqs -B /c/liboqs/build -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release -G Ninja
cmake --build /c/liboqs/build
# Copy DLL to the expected location
mkdir -p ~/AppData/Local/_oqs/bin
cp /c/liboqs/build/bin/liboqs.dll ~/AppData/Local/_oqs/bin/oqs.dll
```

### 3. Install Python dependencies

```bash
pip install -r requirements.txt
```

### 4. Configure environment

```bash
cp Cripto/.env.example Cripto/.env   # or create manually
# Edit Cripto/.env with your values (see Environment Variables section)
```

### 5. Initialise the database

```bash
python manage.py migrate
python manage.py initialize_roles_permissions
python manage.py setup_organizations
python manage.py create_pqc_role
```

### 6. Run

```bash
python manage.py runserver
# Optional: Telegram bot
python manage.py run_telegram_bot
```

---

## Setup — Docker / Render

The included `Dockerfile` builds liboqs from source and runs the application with Gunicorn. No external library installation is needed.

```bash
# Build locally
docker build -t fortyseal .
docker run -p 10000:10000 --env-file Cripto/.env fortyseal
```

### Deploy to Render

1. Push the repository (including `Dockerfile`) to GitHub/GitLab
2. Connect the repo to your existing Render Web Service
3. Render auto-detects the `Dockerfile` and switches to Docker runtime
4. Add all environment variables in **Render → Environment**
5. The first build takes ~10 minutes (liboqs compilation); subsequent builds use Docker layer cache

---

## Management Commands

```bash
# Roles & permissions
python manage.py initialize_roles_permissions
python manage.py setup_permissions
python manage.py create_pqc_role
python manage.py create_org_admin_role

# PQC key management
python manage.py generate_user_keys     # generate PQC key triples for all users
python manage.py rotate_keys            # rotate expired keys
python manage.py generate_pqc_crl       # emit a new CRL snapshot (Dilithium-5 signed)
python manage.py compute_key_scores     # compute security scores for all key pairs

# Blockchain
python manage.py verify_merkle_roots    # verify all block Merkle roots
python manage.py backup_blockchain      # encrypted backup of the blockchain
python manage.py restore_blockchain     # restore from backup

# Seeding (development)
python manage.py seed_b2b_orgs
python manage.py seed_b2b_activity
python manage.py seed_b2c_test
python manage.py create_test_users

# Operations
python manage.py update_storage_usage
python manage.py update_overdue_invoices
python manage.py cleanup_transaction_files
python manage.py run_telegram_bot
```

---

## API Overview

All PQC API endpoints are mounted under `/pqc/api/v1/`.

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/pqc/api/v1/kem/encapsulate/` | Encapsulate a shared secret (ML-KEM-1024) |
| `POST` | `/pqc/api/v1/sign/` | Sign a payload (Dilithium-5 / SLH-DSA) |
| `POST` | `/pqc/api/v1/verify/` | Verify a PQC signature |
| `POST` | `/pqc/api/v1/data-key/generate/` | Generate a data encryption key |
| `GET`  | `/pqc/api/v1/crl/` | Fetch the current CRL snapshot |
| `POST` | `/pqc/api/v1/crl/revoke/` | Revoke a key pair |
| `POST` | `/pqc/api/v1/external/register-keys/` | Register external (M2M) PQC public keys |
| `GET`  | `/swagger/` | OpenAPI / Swagger UI |

---

## Use Cases

### B2B — Encrypted Transaction Exchange

An organisation user sends a document to a colleague:

1. Sender's KEM public key (ML-KEM-1024) is fetched from `PQCKeyPair`
2. Document is encrypted with **FS-PQC-1.0** (KEM + ChaCha20-Poly1305)
3. The encrypted blob is signed with the sender's **Dilithium-5** key
4. The transaction is mined into the internal **blockchain**
5. On receipt, signature is verified against the **CRL** before decryption

### B2C — Personal Encrypted Documents

A personal account user stores a file:

1. User generates a PQC key triple (ML-KEM-1024 + Dilithium-5 + SLH-DSA)
2. File is encrypted client-side with the user's own public key
3. Optional signature with preferred algorithm (Dilithium-5 or SLH-DSA)
4. Document is stored with full FS-PQC-1.0 metadata (HMAC, anti-replay token, unique binding)

### M2M — External API Integration

An external system registers a **Falcon-1024** signing key and an **ML-KEM-1024** encryption key via `/api-suite/`. Subsequent API calls carry a Falcon-signed request body that FortySeal verifies before processing.

---

## Security Model

| Layer | Mechanism |
|-------|-----------|
| Data confidentiality | ML-KEM-1024 + HKDF-SHA256 + ChaCha20-Poly1305 (IND-CCA2) |
| Data integrity | ChaCha20-Poly1305 AEAD tag + metadata HMAC-SHA256 |
| Authentication | ML-DSA-87 / SLH-DSA / Falcon-1024 digital signatures |
| Key revocation | Dilithium-5-signed CRL with epoch-based propagation |
| Key protection at rest | AES-256-GCM + Argon2id KDF (user password) |
| Anti-replay | HMAC-SHA256 token (nonce + msg_id + timestamp) |
| Blockchain integrity | SHA-256 PoW + Merkle root + fork protection |
| Audit | Append-only `AuditLog` with `CRITICAL` / `HIGH` severity events |
| Legacy format | Kyber v0 blocked by default (`PQC_BLOCK_V0=True`) |

---

## Roadmap

### v1.1 — Hardening
- [ ] Replace in-memory `ChannelLayer` with Redis-backed layer for multi-worker WebSocket support
- [ ] Full Celery/Redis wiring for async task processing
- [ ] Hardware entropy source integration (HSM / TPM)
- [ ] Automated key rotation scheduler (Celery Beat)

### v1.2 — Protocol
- [ ] Hybrid PQC + X25519 KEM (draft IETF hybrid KEM)
- [ ] FS-PQC-2.0 envelope with compressed block format
- [ ] ML-KEM-768 support for lower-security-level contexts

### v1.3 — Ecosystem
- [ ] Browser extension: full in-browser PQC key generation (WebAssembly liboqs)
- [ ] Mobile SDK (React Native) with liboqs bindings
- [ ] Federated CRL across organisations

### v2.0 — Compliance
- [ ] FIPS 140-3 module boundary documentation
- [ ] SOC 2 Type II audit preparation
- [ ] GDPR key-erasure protocol (cryptographic shredding)

---

## License

Proprietary — © FortySeal Technology. All rights reserved.
