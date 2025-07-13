#!/bin/zsh

#
# Uploads a file to Cloudinary via a secure, signed request and returns a Markdown image link.
#
# USAGE:
#   ./cloud.sh [FILE_PATH]
#
# REQUIREMENTS:
#   - Your environment (e.g., ~/.zshrc) must contain the following variables:
#     - CLOUDINARY_CLOUD_NAME
#     - CLOUDINARY_API_KEY
#     - CLOUDINARY_API_SECRET
#   - `jq` and `shasum` must be installed.
#

# --- Validation ---
# Check for dependencies
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install it (e.g., 'brew install jq')." >&2
    exit 1
fi
if ! command -v shasum &> /dev/null; then
    echo "Error: shasum is not installed. This is typically included in coreutils." >&2
    exit 1
fi

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 [FILE_PATH]" >&2
    exit 1
fi

FILE_PATH="$1"

if [ ! -f "$FILE_PATH" ]; then
    echo "Error: File not found at '$FILE_PATH'" >&2
    exit 1
fi

# --- Load Environment ---
# Check if core variables are set; if not, try to source from ~/.zshrc
if [ -z "$CLOUDINARY_CLOUD_NAME" ] || [ -z "$CLOUDINARY_API_KEY" ] || [ -z "$CLOUDINARY_API_SECRET" ]; then
    if [ -f ~/.zshrc ]; then
        source ~/.zshrc
    else
        echo "Error: ~/.zshrc not found to source environment variables." >&2
        exit 1
    fi
fi

# If separate variables are still not set, check for the CLOUDINARY_URL
if [ -z "$CLOUDINARY_CLOUD_NAME" ] || [ -z "$CLOUDINARY_API_KEY" ] || [ -z "$CLOUDINARY_API_SECRET" ]; then
    if [ -n "$CLOUDINARY_URL" ]; then
        echo "Parsing credentials from CLOUDINARY_URL..." >&2
        # Parse the URL (format: cloudinary://api_key:api_secret@cloud_name)
        CLOUDINARY_CLOUD_NAME=$(echo $CLOUDINARY_URL | awk -F'@' '{print $2}')
        CREDENTIALS_PART=$(echo $CLOUDINARY_URL | awk -F'//' '{print $2}' | awk -F'@' '{print $1}')
        CLOUDINARY_API_KEY=$(echo $CREDENTIALS_PART | awk -F':' '{print $1}')
        CLOUDINARY_API_SECRET=$(echo $CREDENTIALS_PART | awk -F':' '{print $2}')
    fi
fi

# Final check for all required variables
if [ -z "$CLOUDINARY_CLOUD_NAME" ] || [ -z "$CLOUDINARY_API_KEY" ] || [ -z "$CLOUDINARY_API_SECRET" ]; then
    echo "Error: One or more required Cloudinary variables are not set." >&2
    echo "Please set either CLOUDINARY_URL or the following three variables:" >&2
    echo "  - CLOUDINARY_CLOUD_NAME" >&2
    echo "  - CLOUDINARY_API_KEY" >&2
    echo "  - CLOUDINARY_API_SECRET" >&2
    exit 1
fi

# --- Signature ---
# Generate a timestamp for the signature
TIMESTAMP=$(date +%s)

# Create the signature string and SHA1 hash it
SIGNATURE_STRING="timestamp=${TIMESTAMP}${CLOUDINARY_API_SECRET}"
SIGNATURE=$(echo -n "$SIGNATURE_STRING" | shasum -a 1 | awk '{print $1}')

echo "Uploading to Cloudinary cloud: $CLOUDINARY_CLOUD_NAME..." >&2

# --- Upload ---
# Use curl to upload the file with the signature for a secure, signed request
RESPONSE=$(curl -s -X POST "https://api.cloudinary.com/v1_1/${CLOUDINARY_CLOUD_NAME}/image/upload" \
  -F "file=@${FILE_PATH}" \
  -F "api_key=${CLOUDINARY_API_KEY}" \
  -F "timestamp=${TIMESTAMP}" \
  -F "signature=${SIGNATURE}")

# --- Process Response ---
# Check for a successful upload response (check for "secure_url")
if ! echo "$RESPONSE" | jq -e '.secure_url' > /dev/null; then
    echo "Error: Upload failed." >&2
    echo "Response: $RESPONSE" >&2
    exit 1
fi

# Extract the URL using jq
SECURE_URL=$(echo "$RESPONSE" | jq -r '.secure_url')
FILENAME=$(basename "$FILE_PATH")

# --- Output and Copy Markdown Link ---
MARKDOWN_LINK="![${FILENAME}](${SECURE_URL})"

# Print the link to standard output
echo "$MARKDOWN_LINK"

# Copy the link to the clipboard
if command -v pbcopy &> /dev/null; then
    echo -n "$MARKDOWN_LINK" | pbcopy
    echo "✅ Markdown link copied to clipboard." >&2
else
    echo "Warning: pbcopy not found. Could not copy to clipboard." >&2
fi
