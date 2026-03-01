#!/bin/bash

# Simple activation script for the virtual environment

VENV_DIR="venv"

if [ ! -d "$VENV_DIR" ]; then
    echo "Error: Virtual environment not found"
    echo "Run './setup_env.sh' first to create it"
    exit 1
fi

echo "Activating virtual environment..."
source "$VENV_DIR/bin/activate"

if [ $? -eq 0 ]; then
    echo "Environment activated. Python: $(which python3)"
    echo "To deactivate, run: deactivate"
else
    echo "Failed to activate environment"
    exit 1
fi

# Start a new shell with the venv activated
exec bash