#!/bin/bash
set -e

source /opt/ros/jazzy/setup.bash
source /home/husky/.bashrc

cd /home/husky/muninn/backend

exec uvicorn muninn_backend:app --host 0.0.0.0 --port 8000
