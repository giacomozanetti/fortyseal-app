FROM python:3.11-slim

# Dipendenze sistema per compilare liboqs C library
RUN apt-get update && apt-get install -y \
    cmake ninja-build git gcc g++ libssl-dev libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Compila e installa liboqs (NIST FIPS 203/204/205)
# Pin al tag corrispondente a liboqs-python==0.14.1 per garantire compatibilità
# del wire format (ML-KEM/Kyber ha già cambiato formato una volta tra versioni).
# Aggiornare ENTRAMBI il tag qui e la versione in requirements.txt insieme.
# RUN git clone --depth 1 --branch 0.14.0 \
#        https://github.com/open-quantum-safe/liboqs.git /tmp/liboqs \
#    && cmake -S /tmp/liboqs -B /tmp/liboqs/build \
#        -DBUILD_SHARED_LIBS=ON \
#        -DCMAKE_BUILD_TYPE=Release \
#        -DOQS_BUILD_ONLY_LIB=ON \
#        -DCMAKE_INSTALL_PREFIX=/usr/local \
#        -G Ninja \
#    && cmake --build /tmp/liboqs/build --parallel 4 \
#    && cmake --install /tmp/liboqs/build \
#    && rm -rf /tmp/liboqs \
#    && ldconfig

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Normalizza i fine-riga degli script shell a LF: su Windows i .sh vengono spesso
# salvati con CRLF, e il \r finale rompe lo shebang ("env: 'bash\r': No such file").
RUN sed -i 's/\r$//' start.sh build.sh 2>/dev/null || sed -i 's/\r$//' start.sh
RUN chmod +x start.sh

EXPOSE 10000

CMD ["gunicorn", "Cripto.wsgi:application", "--bind", "0.0.0.0:10000", "--workers", "2", "--timeout", "120"]
