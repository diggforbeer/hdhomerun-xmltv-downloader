# Use an official Python base image
FROM python:3.13-slim

# Install required packages
RUN apt-get update && apt-get install -y \
    cron \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy shell script and requirements
COPY download_guide_data.sh /app/download_guide_data.sh
COPY requirements.txt /app/requirements.txt

# Make shell script executable
RUN chmod +x /app/download_guide_data.sh

# Install Python dependencies
RUN pip install --no-cache-dir -r /app/requirements.txt

# Add crontab entry to run script every 6 hours
RUN echo "*/5 * * * * echo '[CRON] Running guide update at $(date)' | tee /proc/1/fd/1; /app/download_guide_data.sh 2>&1 | tee -a /app/cron.log | tee /proc/1/fd/1" > /etc/cron.d/epg_update
RUN chmod 0644 /etc/cron.d/epg_update
RUN crontab /etc/cron.d/epg_update

# Run guide script at startup, then keep cron running in foreground
CMD /app/download_guide_data.sh && cron -f