#!/bin/bash
cd backend 2>/dev/null || true
source venv/bin/activate 2>/dev/null || source ../venv/bin/activate
python app.py
