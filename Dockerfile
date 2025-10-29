FROM python:3.9-slim

WORKDIR /app

# Installa dipendenze di sistema
RUN apt-get update && apt-get install -y     gcc     && rm -rf /var/lib/apt/lists/*

# Copia requirements e installa dipendenze Python
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copia applicazione
COPY . .

# Crea utente non-root per sicurezza
RUN useradd -m -r app && chown -R app:app /app
RUN chmod -R 755 /app

USER app

# Esponi porta
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3     CMD curl -f http://localhost:8000/worker/health || exit 1

# Comando di avvio standard Gunicorn (usando il modulo 'application')
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--access-logfile", "-", "application:app"]
