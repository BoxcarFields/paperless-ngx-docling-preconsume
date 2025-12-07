# Paperless-ngx Docling Pre-consume Script

Bring the power of [Docling](https://github.com/docling-project/docling) to your [Paperless-ngx](https://github.com/paperless-ngx/paperless-ngx) instance!

This project provides a pre-consume script for Paperless-ngx that automatically processes incoming documents (PDF, Images, Office Docs, HTML) using a local Docling server. It extracts high-quality text and structure (Markdown) and saves it as a sidecar text file, allowing Paperless-ngx to index the content with superior accuracy compared to standard OCR tools.

## Features
- **Advanced OCR & Extraction**: Uses Docling's AI models to parse complex layouts, tables, and diverse document formats.
- **Sidecar Generation**: Creates a `.txt` sidecar file containing the extracted Markdown, which Paperless-ngx automatically ingests as the document content.
- **Format Support**: Handles PDFs, Images, DOCX, PPTX, HTML, and more (everything Docling supports).
- **Graceful Fallback**: Skips processing if Docling is unreachable or the file type is unsupported, allowing Paperless to proceed with its default behavior.

## Prerequisites
1.  **Paperless-ngx**: A running instance of Paperless-ngx.
2.  **Docling Server**: A running instance of `docling-serve`.

## Installation

### 1. Deploy Docling
Add the Docling service to your `docker-compose.yml`. 
> [!IMPORTANT]  
> You **must** set a custom `HOME` directory and mount a writable volume to it to avoid permission errors with the container's internal users.

```yaml
  docling:
    image: quay.io/docling-project/docling-serve-cu128 # or cpu version
    container_name: docling
    environment:
      - UVICORN_WORKERS=1
      - DOCLING_SERVE_MAX_MEM=8G
      - DOCLING_SERVE_ENABLE_UI=true
      # Critical: Set HOME to a custom writable path for cache/models
      - HOME=/home/docling 
    volumes:
      # Mount a volume to persist models and cache
      - ./docling_cache:/home/docling
    ports:
      - "5001:5001"
    restart: unless-stopped
```

### 2. Add the Script
1.  Download `docling-preconsume.sh` and place it in a directory accessible to your Paperless container (e.g., alongside your `docker-compose.yml`).
2.  Make the script executable:
    ```bash
    chmod +x docling-preconsume.sh
    ```

### 3. Configure Paperless-ngx
Update your `paperless-ngx` service in `docker-compose.yml` to mount the script and tell Paperless to use it.

```yaml
  webserver:
    image: ghcr.io/paperless-ngx/paperless-ngx:latest
    # ... other settings ...
    environment:
      # Path inside the container
      - PAPERLESS_PRE_CONSUME_SCRIPT=/usr/src/paperless/scripts/docling-preconsume.sh
    volumes:
      # Mount the script into the container
      - ./docling-preconsume.sh:/usr/src/paperless/scripts/docling-preconsume.sh:ro
```

### 4. Review & Restart
Recreate your containers to apply the changes:
```bash
docker compose up -d
```

## Configuration

You can configure the Docling endpoint by setting an environment variable in your `webserver` container (optional, defaults to `http://docling:5001/v1/convert/file`).

```yaml
    environment:
      - DOCLING_ENDPOINT=http://my-custom-docling-host:5001/v1/convert/file
```

## How It Works
1.  Paperless detects a new file in the consume folder.
2.  It triggers the `docling-preconsume.sh` script *before* processing.
3.  The script checks the file type (PDF/Image/Office/HTML).
4.  It sends the file to the Docling API.
5.  Docling returns the extracted Markdown content.
6.  The script saves this content to a `.txt` file with the same name as the original document.
7.  Paperless consumes the original document and uses the text from the `.txt` sidecar for indexing/search.

## Troubleshooting
- **Permission Denied in Docling logs**: Ensure you have set `HOME=/home/docling` (or another writable path) and mounted the volume correctly as shown in the Installation step.
- **Script fails**: Check Paperless logs (`docker logs paperless-ngx`) for output from the pre-consume script.

## License

This project is licensed under the MIT License. Use it freely in your own homelab or project!
