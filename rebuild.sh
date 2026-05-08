#!/bin/bash
# Kill existing processes
for pid in 91586 91321 91377 91588; do
    kill -9 $pid 2>/dev/null
done
pkill -9 -f flutter 2>/dev/null
pkill -9 -f dart 2>/dev/null
pkill -9 -f Runner 2>/dev/null

sleep 3

# Rebuild and run
cd /Users/cyc_joshua/Documents/CYC/TRAX/App-TRAX/trax_app
flutter run -d "iPhone 17 Pro" 2>&1
