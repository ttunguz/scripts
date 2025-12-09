#!/bin/zsh

#
# Uploads a file to Cloudinary via a secure, signed request and returns a Hugo shortcode or Markdown link.
#
# USAGE:
#   ./cloud.sh [FILE_PATH]                    # Returns email_image shortcode (default)
#   ./cloud.sh [FILE_PATH] --markdown         # Returns standard Markdown image link
#   ./cloud.sh [FILE_PATH] --width 600 --height 400  # Custom dimensions (default: 540x360)
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

# Parse command line arguments
FILE_PATH=""
OUTPUT_MODE="shortcode"  # Default to shortcode
WIDTH="540"  # Default width
HEIGHT="360"  # Default height

while [[ $# -gt 0 ]]; do
    case $1 in
        --markdown)
            OUTPUT_MODE="markdown"
            shift
            ;;
        --width)
            WIDTH="$2"
            shift 2
            ;;
        --height)
            HEIGHT="$2"
            shift 2
            ;;
        *)
            if [ -z "$FILE_PATH" ]; then
                FILE_PATH="$1"
            else
                echo "Error: Unexpected argument: $1" >&2
                echo "Usage: $0 [FILE_PATH] [--markdown] [--width N] [--height N]" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [ -z "$FILE_PATH" ]; then
    echo "Usage: $0 [FILE_PATH] [--markdown] [--width N] [--height N]" >&2
    exit 1
fi

if [ ! -f "$FILE_PATH" ]; then
    echo "Error: File not found at '$FILE_PATH'" >&2
    exit 1
fi

# --- Load Environment ---
# Check if core variables are set; if not, try Keychain first, then ~/.zshrc
if [ -z "$CLOUDINARY_CLOUD_NAME" ] || [ -z "$CLOUDINARY_API_KEY" ] || [ -z "$CLOUDINARY_API_SECRET" ]; then
    # Try Keychain first (macOS)
    if command -v security &> /dev/null; then
        KEYCHAIN_CLOUD_NAME=$(security find-generic-password -s "CLOUDINARY_CLOUD_NAME" -a "tomasztunguz" -w 2>/dev/null)
        KEYCHAIN_API_KEY=$(security find-generic-password -s "CLOUDINARY_API_KEY" -a "tomasztunguz" -w 2>/dev/null)
        KEYCHAIN_API_SECRET=$(security find-generic-password -s "CLOUDINARY_SECRET" -a "tomasztunguz" -w 2>/dev/null)
        KEYCHAIN_URL=$(security find-generic-password -s "CLOUDINARY_URL" -a "tomasztunguz" -w 2>/dev/null)

        if [ -n "$KEYCHAIN_CLOUD_NAME" ] && [ -n "$KEYCHAIN_API_KEY" ] && [ -n "$KEYCHAIN_API_SECRET" ]; then
            CLOUDINARY_CLOUD_NAME="$KEYCHAIN_CLOUD_NAME"
            CLOUDINARY_API_KEY="$KEYCHAIN_API_KEY"
            CLOUDINARY_API_SECRET="$KEYCHAIN_API_SECRET"
            echo "✅ Loaded credentials from Keychain." >&2
        elif [ -n "$KEYCHAIN_URL" ]; then
            # If individual credentials not found, try parsing CLOUDINARY_URL
            CLOUDINARY_URL="$KEYCHAIN_URL"
            echo "✅ Loaded CLOUDINARY_URL from Keychain." >&2
        fi
    fi
fi

# If still not set, try to source from ~/.zshrc
if [ -z "$CLOUDINARY_CLOUD_NAME" ] || [ -z "$CLOUDINARY_API_KEY" ] || [ -z "$CLOUDINARY_API_SECRET" ]; then
    if [ -f ~/.zshrc ]; then
        source ~/.zshrc
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

# Extract the URL and public_id using jq
SECURE_URL=$(echo "$RESPONSE" | jq -r '.secure_url')
PUBLIC_ID=$(echo "$RESPONSE" | jq -r '.public_id')
FILENAME=$(basename "$FILE_PATH")

# --- Generate Output Based on Mode ---
if [ "$OUTPUT_MODE" = "markdown" ]; then
    # Standard Markdown link
    OUTPUT="![${FILENAME}](${SECURE_URL})"
else
    # Hugo email_image shortcode format
    # Remove file extension from filename for alt text
    ALT_TEXT="${FILENAME%.*}"
    OUTPUT="{{< email_image src=\"${PUBLIC_ID}\" alt=\"${ALT_TEXT}\" width=\"${WIDTH}\" height=\"${HEIGHT}\" >}}"
fi

# Print the output to standard output
echo "$OUTPUT"

# Copy to clipboard
if command -v pbcopy &> /dev/null; then
    echo -n "$OUTPUT" | pbcopy
    if [ "$OUTPUT_MODE" = "markdown" ]; then
        echo "✅ Markdown link copied to clipboard." >&2
    else
        echo "✅ Email image shortcode copied to clipboard (width=${WIDTH}, height=${HEIGHT})." >&2
    fi
else
    echo "Warning: pbcopy not found. Could not copy to clipboard." >&2
fi
