#!/usr/bin/env bash
# docling-preconsume.sh
# Extract text/markdown from document using Docling and save as sidecar file for Paperless-ngx.

INPUT_FILE="$1"
if [ -z "$INPUT_FILE" ]; then
    INPUT_FILE="$DOCUMENT_SOURCE_PATH"
fi

if [ -z "$INPUT_FILE" ]; then
    echo "Error: No input file specified."
    exit 1
fi

# Only process supported formats (avoid loops with .txt)
MIME_TYPE=$(file -b --mime-type "$INPUT_FILE")
case "$MIME_TYPE" in
    application/pdf|image/*|application/vnd.openxmlformats-officedocument.*|application/msword|application/vnd.ms-*|text/html)
        echo "Processing $INPUT_FILE ($MIME_TYPE) with Docling..."
        ;;
    *)
        echo "Skipping $INPUT_FILE ($MIME_TYPE) - not a supported format."
        exit 0
        ;;
esac

# Docling Endpoint
DOCLING_ENDPOINT="${DOCLING_ENDPOINT:-http://docling:5001/v1/convert/file}"

# Check connectivity
DOCLING_HEALTH_URL="$(echo "$DOCLING_ENDPOINT" | sed 's|/v1/convert/file|/health|')"
# If endpoint was custom (not ending in /v1/convert/file), assume standard health path relative to host, or just try the endpoint itself
if [[ "$DOCLING_HEALTH_URL" == "$DOCLING_ENDPOINT" ]]; then
    # Fallback to simple check if we couldn't derive health URL easily
    curl -s "$DOCLING_ENDPOINT" >/dev/null
else 
    curl -s "$DOCLING_HEALTH_URL" >/dev/null
fi

if [ $? -ne 0 ]; then
   # Ultimate fallback: try the base URL health if widely known or just warn
   echo "Warning: Docling service not reachable. Skipping OCR."
   exit 0 
fi

# Send file to Docling
RESPONSE=$(curl -s -X POST "$DOCLING_ENDPOINT" -F "files=@$INPUT_FILE")

# Extract Markdown content using Python
MD_CONTENT=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('document', {}).get('md_content', ''))")

if [ -z "$MD_CONTENT" ]; then
    echo "Warning: No content returned from Docling. Skipping sidecar generation."
    exit 0
fi

# Create sidecar path (same directory, same basename, .txt extension)
DIR=$(dirname "$INPUT_FILE")
BASENAME=$(basename "$INPUT_FILE")
FILENAME="${BASENAME%.*}"
SIDECAR_PATH="$DIR/$FILENAME.txt"

# Write content to sidecar
echo "$MD_CONTENT" > "$SIDECAR_PATH"

if [ $? -eq 0 ]; then
    echo "Created sidecar file at $SIDECAR_PATH"
else
    echo "Error: Failed to write sidecar file."
    exit 1
fi

exit 0
