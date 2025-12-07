#! /usr/bin/env bash
# Post-consume arguments:
# $1: Document ID
# $2: Detailed file name
# $3: Path to original file
DOCUMENT_ID="$1"
INPUT_FILE="$3"

if [ -z "$DOCUMENT_ID" ] || [ -z "$INPUT_FILE" ]; then
    echo "Error: Missing arguments. Usage: $0 <document_id> <filename> <path>"
    exit 1
fi

# Ensure API Token and URL are set
if [ -z "$PAPERLESS_API_TOKEN" ]; then
    echo "Error: PAPERLESS_API_TOKEN is not set."
    exit 1
fi
PAPERLESS_API_URL="${PAPERLESS_API_URL:-${PAPERLESS_BASE_URL:-http://localhost:8000}}"

# Only process supported formats (avoid loops)
MIME_TYPE=$(file -b --mime-type "$INPUT_FILE")
case "$MIME_TYPE" in
    application/pdf|image/*|application/vnd.openxmlformats-officedocument.*|application/msword|application/vnd.ms-*|text/html)
        echo "Processing Document #$DOCUMENT_ID: $INPUT_FILE ($MIME_TYPE) with Docling..."
        ;;
    *)
        echo "Skipping Document #$DOCUMENT_ID ($MIME_TYPE) - not a supported format."
        exit 0
        ;;
esac

# Docling Endpoint
# Use DOCLING_URL from env if available (e.g. from stack.env), otherwise default
DOCLING_BASE="${DOCLING_URL:-http://docling:5001}"
# Remove trailing slash if present to avoid double slashes
DOCLING_BASE="${DOCLING_BASE%/}"
DOCLING_ENDPOINT="${DOCLING_ENDPOINT:-${DOCLING_BASE}/v1/convert/file}"

# Connectivity check (simplified)
curl -s "$(echo "$DOCLING_ENDPOINT" | sed 's|/v1/convert/file|/health|')" >/dev/null || curl -s "$DOCLING_ENDPOINT" >/dev/null
if [ $? -ne 0 ]; then
   echo "Warning: Docling service not reachable. Skipping."
   exit 0 
fi

# Send file to Docling
TARGET_FILE="$INPUT_FILE"
TEMP_PDF=""
TEMP_RASTER_PDF=""

if [ "$DOCLING_FORCE_OCR" = "1" ] || [ "$DOCLING_FORCE_OCR" = "true" ]; then
    if [ "$MIME_TYPE" = "application/pdf" ]; then
        echo "Forcing OCR by rasterizing PDF..."
        TEMP_RASTER_PDF=$(mktemp --suffix=.pdf)
        # Lossless rasterization (Zip compression) to ensure clean text for OCR/Docling
        convert -density 300 "$INPUT_FILE" png:- | convert - -compress Zip "$TEMP_RASTER_PDF"
        if [ $? -eq 0 ]; then
             TARGET_FILE="$TEMP_RASTER_PDF"
        else
             echo "Warning: Rasterization failed. Proceeding with original file."
             rm -f "$TEMP_RASTER_PDF"
             TEMP_RASTER_PDF=""
        fi
    fi
fi

RESPONSE=$(curl -s -X POST "$DOCLING_ENDPOINT" -F "files=@$TARGET_FILE")

# Cleanup temp file
if [ -n "$TEMP_RASTER_PDF" ]; then
    rm -f "$TEMP_RASTER_PDF"
fi

# Extract Markdown content using Python
MD_CONTENT=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('document', {}).get('md_content', ''))")

# Fix Unicode artifacts: Decode /uniXXXX to characters (e.g. /uni004F -> O)
# The artifacts match Hex ASCII codes. We use Python for robust decoding.
MD_CONTENT=$(echo "$MD_CONTENT" | python3 -c "
import sys, re

def replace_uni(match):
    try:
        # Extract the hex code (last 4 chars)
        hex_code = match.group(0)[4:]
        return chr(int(hex_code, 16))
    except (ValueError, OverflowError):
        return match.group(0)

content = sys.stdin.read()
# Regex to find /uni followed by 4 hex digits
decoded = re.sub(r'/uni[0-9A-Fa-f]{4}', replace_uni, content)
print(decoded)
")

# Clean up Markdown: Remove images to avoid base64 spam in search index
MD_CONTENT=$(echo "$MD_CONTENT" | sed '/!\[.*\](.*)/d')

if [ -z "$MD_CONTENT" ]; then
    echo "Warning: No content returned from Docling. Skipping update."
    exit 0
fi

# Sanitize Markdown for JSON (escape double quotes, backslashes, newlines)
# Python is safer for this JSON encoding than sed
JSON_PAYLOAD=$(python3 -c "import sys, json; print(json.dumps({'content': sys.stdin.read()}))" <<< "$MD_CONTENT")

# Patch the document content via API
echo "Updating Document #$DOCUMENT_ID content..."
API_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH "$PAPERLESS_API_URL/api/documents/$DOCUMENT_ID/" \
    -H "Authorization: Token $PAPERLESS_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD")

# Explicitly clear Docling converters to free memory
# This is crucial as Docling does not automatically unload models/buffers
echo "Triggering Docling memory cleanup..."
curl -s -X POST "${DOCLING_BASE}/v1/clear/converters" >/dev/null
curl -s -X POST "${DOCLING_BASE}/v1/clear/results" >/dev/null || true # Optional: clear results too if available

if [ "$API_RESPONSE" -eq 200 ]; then
    echo "Successfully updated document #$DOCUMENT_ID with Docling content."
else
    echo "Error: Failed to update document #$DOCUMENT_ID. API returned $API_RESPONSE"
    exit 1
fi

exit 0
