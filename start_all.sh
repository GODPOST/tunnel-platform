#!/bin/bash
echo "🚀 Starting Tunnel Platform..."

# Start backend in background
echo "Starting backend..."
./start_backend.sh &
BACKEND_PID=$!

# Wait a bit for backend to start
sleep 3

# Start frontend
echo "Starting frontend..."
./start_frontend.sh

# When frontend exits, kill backend
kill $BACKEND_PID 2>/dev/null
