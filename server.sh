#!/bin/bash
# Simple script to run the Vibe Blocks MCP server with uvicorn

# Check if uv is installed
if ! command -v uv &> /dev/null
then
    echo "Error: uv is not installed. Please install it first: https://github.com/astral-sh/uv#installation" 
    exit 1
fi

# Check if uvicorn is installed via uv, install if not
if ! uv pip freeze | grep -q "uvicorn=="
then
    echo "uvicorn not found via uv. Installing..."
    uv pip install uvicorn
    if [ $? -ne 0 ]; then
        echo "Failed to install uvicorn. Please install it manually." >&2
        exit 1
    fi
fi

# Navigate to the script's directory to ensure correct relative paths
cd "$(dirname "$0")"

# Run the server
echo "Starting Vibe Blocks MCP Server (http://localhost:8000)..."
uvicorn src.roblox_mcp.server:app --port 8000 --reload 