# Munnin 🐦‍⬛

Muninn is a ROS2 robot operations platform for monitoring system health, launching robot subsystems, and managing experiment data recording through a Flutter-based dashboard and FastAPI backend.

# Repository Structure
```text
muninn/
├── backend/
│   ├── muninn_backend.py
│   ├── config/
│   │   └── muninn.yaml
│   ├── requirements.txt
│   └── README.md
│
├── dashboard/
│   └── Flutter app
│
├── docs/
│   └── architecture.md
│
├── README.md
└── .gitignore
```


# Architecture
```text
Flutter Dashboard
       │
       │ REST API
       ▼
Muninn Backend
       │
       │ ros2 launch / ros2 bag / ros2 node list
       ▼
ROS2 Robot
```
# Running Muninn

### Start the Backend

From the backend directory:

```bash
cd backend
uvicorn muninn_backend:app --host 0.0.0.0 --port 8000
```

The FastAPI API will be available at:

```text
http://localhost:8000
```

Interactive API documentation:

```text
http://localhost:8000/docs
```

---

### Start the Dashboard

From the dashboard directory:

```bash
cd dashboard
flutter run -d chrome
```

---

### Backend Configuration

For local development, configure the backend URL in `lib/main.dart`:

```dart
const String backendUrl = 'http://localhost:8000';
```

When connecting to a Muninn instance running on another machine, replace `localhost` with the robot's IP address:

```dart
const String backendUrl = 'http://ROBOT_IP:8000';
```

Example:

```dart
const String backendUrl = 'http://192.168.1.100:8000';
```
