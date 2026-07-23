#!/usr/bin/env bash
# =============================================================================
# build.sh — Script di build per Render (e ambienti CI senza Docker)
#
# Configura questo script come "Build Command" su Render:
#   ./build.sh
#
# Differenza con start.sh:
#   build.sh  → eseguito UNA VOLTA al deploy (compilazione, dipendenze, assets)
#   start.sh  → eseguito ad ogni avvio del processo web (migrate + gunicorn)
# =============================================================================
set -e

# ---------------------------------------------------------------------------
# 1. Dipendenze Python
# ---------------------------------------------------------------------------
echo "==> Installing Python dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

# ---------------------------------------------------------------------------
# 2. liboqs C library — richiesta da liboqs-python (oqs) per PQC
#
# Il pacchetto oqs-python include un auto-installer che clona liboqs da GitHub
# e lo compila via cmake. Se eseguito a runtime (start.sh) ciò:
#   - rallenta l'avvio di 30-60 secondi
#   - può fallire se cmake/git non sono disponibili → SystemExit(1)
#   - genera rumore su Sentry (PYTHON-DJANGO-2)
#
# Qui lo pre-installiamo durante il build step così il runtime trova già
# la libreria in $HOME/_oqs (path di default di oqs-python).
# ---------------------------------------------------------------------------
LIBOQS_VERSION="0.14.0"          # tag della C library (≠ liboqs-python 0.14.1 che è il binding Python)
LIBOQS_INSTALL_DIR="${HOME}/_oqs" # path cercato automaticamente da oqs-python

echo "==> Checking liboqs availability..."
if python -c "import oqs; print('liboqs', oqs.oqs_version())" 2>/dev/null; then
    echo "    liboqs already available, skipping build."
else
    echo "    liboqs not found — building from source (branch ${LIBOQS_VERSION})..."

    # Installa le dipendenze di sistema necessarie per la compilazione.
    # Su Render native runner apt-get è disponibile; su altri CI potrebbe fallire
    # silenziosamente (|| true) senza bloccare il build.
    apt-get install -y cmake ninja-build git gcc g++ libssl-dev 2>/dev/null || \
        echo "    WARNING: apt-get not available; build may fail if tools are missing."

    TMP_DIR=$(mktemp -d)
    trap "rm -rf ${TMP_DIR}" EXIT

    echo "    Cloning liboqs ${LIBOQS_VERSION}..."
    git clone --depth 1 --branch "${LIBOQS_VERSION}" \
        https://github.com/open-quantum-safe/liboqs.git "${TMP_DIR}/liboqs"

    echo "    Configuring cmake..."
    cmake -S "${TMP_DIR}/liboqs" -B "${TMP_DIR}/build" \
        -DBUILD_SHARED_LIBS=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DOQS_BUILD_ONLY_LIB=ON \
        -DOQS_ENABLE_SIG_STFL_LMS=ON \
        -DOQS_ENABLE_SIG_STFL_XMSS=ON \
        -DOQS_HAZARDOUS_EXPERIMENTAL_ENABLE_SIG_STFL_KEY_SIG_GEN=ON \
        -DCMAKE_INSTALL_PREFIX="${LIBOQS_INSTALL_DIR}" \
        -G Ninja

    echo "    Building liboqs (parallel 4)..."
    cmake --build "${TMP_DIR}/build" --parallel 4

    echo "    Installing liboqs to ${LIBOQS_INSTALL_DIR}..."
    cmake --install "${TMP_DIR}/build"

    # Verifica che la libreria sia effettivamente caricabile
    if python -c "import oqs; print('liboqs', oqs.oqs_version())" 2>/dev/null; then
        echo "    liboqs installed successfully."
    else
        echo "    WARNING: liboqs build completed but library still not loadable."
        echo "             PQC features will be disabled; app continues without them."
    fi
fi

# ---------------------------------------------------------------------------
# 3. Static files
# ---------------------------------------------------------------------------
echo "==> Collecting static files..."
python manage.py collectstatic --noinput

echo ""
echo "Build complete."
