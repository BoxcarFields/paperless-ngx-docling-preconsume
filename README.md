# Paperless-ngx Docling Consume Script

Bring the power of [Docling](https://github.com/docling-project/docling-serve) to your [Paperless-ngx](https://github.com/paperless-ngx/paperless-ngx) instance!

This project provides a post-consume script for Paperless-ngx that automatically processes incoming documents (PDF, Images, Office Docs, HTML) using a local Docling server. It extracts high-quality text and structure (Markdown) and directly updates the document content in Paperless-ngx via the API, bypassing standard OCR limitations.

## Features
- **Advanced OCR & Extraction**: Uses Docling's AI models to parse complex layouts, tables, and diverse document formats.
- **Direct API Integration**: Updates the document content directly via the Paperless API, ensuring reliable indexing without relying on fragile sidecar file detection.
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
1.  Download `docling-postconsume.sh` and place it in a directory accessible to your Paperless container (e.g., alongside your `docker-compose.yml`).
2.  Make the script executable:
    ```bash
    chmod +x docling-postconsume.sh
    ```

### 3. Configure Paperless-ngx
Update your `paperless-ngx` service in `docker-compose.yml` to mount the script and tell Paperless to use it as a **post-consume** script.

**Crucial:** Ensure the necessary environment variables are set so the script can access the Paperless API and the Docling service.

```yaml
  webserver:
    image: ghcr.io/paperless-ngx/paperless-ngx:latest
    # ... other settings ...
    environment:
      # 1. Enable the Post-Consume Script
      - PAPERLESS_POST_CONSUME_SCRIPT=/usr/src/paperless/scripts/docling-postconsume.sh
      
      # 2. API Configuration (The script inherits these from your environment)
      # Ensure PAPERLESS_API_TOKEN is set in your stack.env or here
      # - PAPERLESS_API_TOKEN=your-token-here 
      
      # The script will try to use PAPERLESS_API_URL, then PAPERLESS_BASE_URL, then localhost
      - PAPERLESS_API_URL=http://localhost:8000
      
      # 3. Docling Configuration (Optional, defaults to http://docling:5001)
      # If you have DOCLING_URL set for other tools, the script will use it automatically
      # - DOCLING_URL=http://docling:5001 

    volumes:
      # Mount the script into the container
      - ./docling-postconsume.sh:/usr/src/paperless/scripts/docling-postconsume.sh:ro
```

### 4. Review & Restart
Recreate your containers to apply the changes:
```bash
docker compose up -d
```

## Configuration

You can configure the Docling endpoint by setting an environment variable in your `webserver` container. 
 - `DOCLING_URL`: Base URL (default: `http://docling:5001`) - **Recommended**
 - `DOCLING_ENDPOINT`: Full endpoint override (default: `DOCLING_URL` + `/v1/convert/file`)

```yaml
    environment:
      - DOCLING_URL=http://my-custom-docling-host:5001
```

## How It Works
1.  Paperless consumes a new file.
2.  It triggers the `docling-postconsume.sh` script *after* processing.
3.  The script checks the file type (PDF/Image/Office/HTML).
4.  It sends the file to the Docling API.
5.  Docling returns the extracted Markdown content.
6.  The script sanitizes the content (fixing unicode artifacts) and patches the document via the Paperless API.
7.  Paperless indexes the new high-quality text.

## Troubleshooting
- **Permission Denied in Docling logs**: Ensure you have set `HOME=/home/docling` (or another writable path) and mounted the volume correctly as shown in the Installation step.
- **Script fails**: Check Paperless logs (`docker logs paperless-ngx`) for output from the post-consume script.

## License

This project is licensed under the MIT License. Use it freely in your own homelab or project!
