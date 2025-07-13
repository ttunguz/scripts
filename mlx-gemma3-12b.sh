#!/bin/bash

# MLX Gemma 3 12B Server Startup Script with Memory Optimizations
# Starts MLX server with Gemma 3 12B model on port 8080
# Includes KV cache management and memory optimizations

MODEL_NAME="mlx-community/gemma-3-12b-it-4bit"
HOST="localhost"
PORT="8080"
MAX_TOKENS="4096"
CONTEXT_SIZE="4096"  # Match Ollama context size setting

# MLX Memory Management Environment Variables
export MLX_METAL_BUFFER_CACHE_LIMIT="2048"  # Limit metal buffer cache (MB)
export MLX_GPU_MEMORY_LIMIT="0.8"           # Use 80% of GPU memory max
export MLX_KV_CACHE_SIZE="4096"             # Set KV cache size limit

echo "Starting MLX server with Gemma 3 12B model and memory optimizations..."
echo "Model: $MODEL_NAME"
echo "Host: $HOST"
echo "Port: $PORT"
echo "Max Tokens: $MAX_TOKENS"
echo "Context Size: $CONTEXT_SIZE"
echo "Memory Management: Enabled"
echo ""

# Clear any existing MLX cache before starting
python3 -c "
try:
    import mlx.core as mx
    mx.metal.clear_cache()
    print('Cleared MLX cache')
except ImportError:
    print('MLX not available for cache clearing')
" 2>/dev/null

# Check if port is already in use
if lsof -i :$PORT > /dev/null 2>&1; then
    echo "Port $PORT is already in use. Checking if it's MLX server..."
    
    # Try to make a simple request to check if it's our MLX server
    if curl -s "http://$HOST:$PORT/v1/models" > /dev/null 2>&1; then
        echo "MLX server is already running on port $PORT"
        exit 0
    else
        echo "Something else is running on port $PORT. Please stop it first."
        exit 1
    fi
fi

# Start MLX server with memory optimizations
echo "Starting MLX server with memory optimizations..."
exec mlx_lm.server \
    --model "$MODEL_NAME" \
    --host "$HOST" \
    --port "$PORT" \
    --max-tokens "$MAX_TOKENS" \
    --temp 0.7
