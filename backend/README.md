# Muninn Backend

Backend service for the Muninn robot operations platform.

Provides a REST API for monitoring ROS2 nodes, launching configured subsystems, and managing rosbag recordings.

## Features

* Monitor required ROS2 nodes
* Launch configured ROS2 launch files
* Stop processes started by Muninn
* Start and stop rosbag recordings
* YAML-based configuration
* FastAPI REST API
* Automatic API documentation (`/docs`)

## Structure

```text
backend/
├── muninn_backend.py
├── config/
│   └── muninn.yaml
├── requirements.txt
└── README.md
```

## Installation

```bash
pip install -r requirements.txt
```

## Run

```bash
uvicorn muninn_backend:app --host 0.0.0.0 --port 8000
```

API documentation:

```text
http://<robot-ip>:8000/docs
```

## Endpoints

| Method | Endpoint         | Description            |
| ------ | ---------------- | ---------------------- |
| GET    | `/status`        | System status          |
| GET    | `/nodes`         | List ROS2 nodes        |
| POST   | `/launch/{node}` | Launch subsystem       |
| POST   | `/stop/{node}`   | Stop subsystem         |
| POST   | `/record/start`  | Start rosbag recording |
| POST   | `/record/stop`   | Stop rosbag recording  |

## Configuration

Subsystems and recording topics are configured in:

```text
config/muninn_backend.yaml
```

## Notes

Muninn only stops processes that it launched itself and will not terminate external ROS2 processes.
