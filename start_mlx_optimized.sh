#!/bin/bash

# MLX Memory-Optimized Server Startup Script
# Uses virtual environment and advanced memory management

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/mlx-env"
PYTHON_SCRIPT="$SCRIPT_DIR/mlx_memory_optimized_server.py"

echo "Starting MLX Memory-Optimized Server..."
echo "Script directory: $SCRIPT_DIR"
echo "Virtual environment: $VENV_DIR"
echo ""

# Check if virtual environment exists
if [ ! -d "$VENV_DIR" ]; then
    echo "Error: Virtual environment not found at $VENV_DIR"
    echo "Please run: cd $SCRIPT_DIR && uv venv mlx-env && source mlx-env/bin/activate && uv pip install mlx-lm"
    exit 1
fi

# Activate virtual environment and run server
echo "Activating virtual environment and starting server..."
source "$VENV_DIR/bin/activate"

# Set memory optimization environment variables
export MLX_METAL_BUFFER_CACHE_LIMIT="2048"
export MLX_GPU_MEMORY_LIMIT="0.8"

# Start the server with all arguments passed through
python3 "$PYTHON_SCRIPT" --model mlx-community/gemma-3-12b-it-4bit --max-cache-size 4096 "$@"