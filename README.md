# HDHomeRun XMLTV Downloader

This project is designed to query an HDHomeRun device for its device ID and download the XMLTV guide data for use in various applications.

## Project Structure

```
hdhomerun-xmltv-downloader
├── src
│   ├── main.py          # Main script to run inside the Docker container
│   └── utils.py         # Utility functions for querying HDHomeRun and processing XMLTV data
├── Dockerfile            # Instructions to build the Docker image
├── requirements.txt      # Python dependencies required for the project
└── README.md             # Documentation for the project
```

## Setup Instructions

1. **Clone the repository:**
   ```
   git clone <repository-url>
   cd hdhomerun-xmltv-downloader
   ```

2. **Build the Docker image:**
   ```
   docker build -t xmltvfromhdhomerun:latest .
   ```

3. **Run the service using Docker Compose:**
   ```
   docker compose up -d
   ```

   This will start the container, run the guide update script at startup, and schedule it to run every 6 hours via cron.

   The container uses environment variables for configuration, which are set in `docker-compose.yml`. You can adjust paths, device IP, and other settings there.

## Usage

Once the container is running, the `download_guide_data.sh` script will automatically query your HDHomeRun device and download the XMLTV guide data. The script runs at startup and every 6 hours thereafter.

## Configuration

Configuration is managed via environment variables in `docker-compose.yml`. You can set:

- `SCRIPT_DIR`: Where temporary and output files are stored
- `PLEX_XML_PATH`, `JELLYFIN_XML_PATH`: Where to copy the guide for Plex/Jellyfin
- `HDHOMERUN_IP`: Your device's IP address
- `MAX_BACKUPS`: Number of backup files to keep

Edit `docker-compose.yml` to change these values as needed.

## Dependencies

This project requires the following Python libraries:
- `requests` for making HTTP requests
- `xml.etree.ElementTree` for parsing XML data

These dependencies are listed in `requirements.txt` and installed automatically in the Docker build.