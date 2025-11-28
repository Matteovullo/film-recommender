FROM python:3.9-slim

WORKDIR /app

# Installa dipendenze di sistema
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copia requirements e installa dipendenze Python
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copia il codice dell'applicazione
COPY . .

# Crea utente non-root per sicurezza
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# Esponi la porta
EXPOSE 5000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:5000/health || exit 1

# Comando di avvio
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "application:app"]
