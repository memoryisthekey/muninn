#!/usr/bin/env python3

import os
import signal
import subprocess
from pathlib import Path

import yaml
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware


BASE_DIR = Path(__file__).resolve().parent
CONFIG_FILE = BASE_DIR / "config" / "muninn_backend.yaml"

app = FastAPI(title="Muninn Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

processes = {}
recording_process = None


def load_config():
    with open(CONFIG_FILE, "r") as f:
        return yaml.safe_load(f)


def bash_env():
    env = os.environ.copy()
    env["ROS_DOMAIN_ID"] = env.get("ROS_DOMAIN_ID", "0")
    env["RMW_IMPLEMENTATION"] = env.get(
        "RMW_IMPLEMENTATION",
        "rmw_fastrtps_cpp",
    )
    return env


def ros_shell(command: str) -> str:
    config = load_config()

    setup_lines = "\n".join(
        f"source {Path(path).expanduser()}"
        for path in config["ros"]["setup_files"]
    )

    return f"""
    set -e
    {setup_lines}
    {command}
    """


def run_bash(command: str):
    return subprocess.check_output(
        ros_shell(command),
        shell=True,
        text=True,
        executable="/bin/bash",
        env=bash_env(),
    )


def start_process(command: str):
    return subprocess.Popen(
        ros_shell(command),
        shell=True,
        executable="/bin/bash",
        env=bash_env(),
        preexec_fn=os.setsid,
    )


def is_alive(process):
    return process is not None and process.poll() is None


def stop_process(process):
    if not is_alive(process):
        return False

    os.killpg(os.getpgid(process.pid), signal.SIGINT)

    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(os.getpgid(process.pid), signal.SIGTERM)
        process.wait(timeout=5)

    return True


@app.get("/")
def root():
    return {
        "ok": True,
        "name": "Muninn Backend",
        "docs": "/docs",
    }


@app.get("/nodes")
def list_ros_nodes():
    try:
        output = run_bash("ros2 node list")
        nodes = [line.strip() for line in output.splitlines() if line.strip()]
        return {
            "ok": True,
            "nodes": nodes,
        }
    except Exception as e:
        return {
            "ok": False,
            "error": str(e),
            "nodes": [],
        }


@app.get("/status")
def status():
    config = load_config()

    try:
        output = run_bash("ros2 node list")
        current_nodes = [line.strip() for line in output.splitlines() if line.strip()]
    except Exception:
        current_nodes = []

    sensor_status = {}

    for key, sensor_cfg in config["sensors"].items():
        expected_node = sensor_cfg.get("ros_node_name")

        sensor_status[key] = {
            "display_name": sensor_cfg.get("display_name", key),
            "ros_node_name": expected_node,
            "running": expected_node in current_nodes if expected_node else None,
            "launched_by_backend": key in processes and is_alive(processes[key]),
        }

    return {
        "ok": True,
        "ros_nodes_visible": current_nodes,
        "all_sensors_launch_running": (
            "all_sensors" in processes and is_alive(processes["all_sensors"])
        ),
        "sensors": sensor_status,
        "recording": is_alive(recording_process),
    }


@app.post("/sensors/start")
def start_all_sensors():
    config = load_config()
    key = "all_sensors"

    if key in processes and is_alive(processes[key]):
        return {
            "ok": True,
            "status": "sensors already running",
        }

    command = config["all_sensors"]["launch_command"]
    process = start_process(command)
    processes[key] = process

    return {
        "ok": True,
        "status": "sensors launched",
        "pid": process.pid,
    }


@app.post("/sensors/stop")
def stop_all_sensors():
    key = "all_sensors"

    if key not in processes or not is_alive(processes[key]):
        return {
            "ok": True,
            "status": "sensors not running from backend",
        }

    stop_process(processes[key])
    processes.pop(key, None)

    return {
        "ok": True,
        "status": "sensors stopped",
    }


@app.post("/sensor/{sensor_key}/start")
def start_sensor(sensor_key: str):
    config = load_config()

    if sensor_key not in config["sensors"]:
        return {
            "ok": False,
            "error": f"Unknown sensor: {sensor_key}",
        }

    if sensor_key in processes and is_alive(processes[sensor_key]):
        return {
            "ok": True,
            "status": "sensor already launched by backend",
            "sensor": sensor_key,
        }

    command = config["sensors"][sensor_key]["launch_command"]
    process = start_process(command)
    processes[sensor_key] = process

    return {
        "ok": True,
        "status": "sensor launched",
        "sensor": sensor_key,
        "pid": process.pid,
    }


@app.post("/sensor/{sensor_key}/stop")
def stop_sensor(sensor_key: str):
    if sensor_key not in processes or not is_alive(processes[sensor_key]):
        return {
            "ok": True,
            "status": "sensor not running from backend",
            "sensor": sensor_key,
        }

    stop_process(processes[sensor_key])
    processes.pop(sensor_key, None)

    return {
        "ok": True,
        "status": "sensor stopped",
        "sensor": sensor_key,
    }


@app.post("/recording/start")
def start_recording():
    global recording_process

    if is_alive(recording_process):
        return {
            "ok": True,
            "status": "already recording",
        }

    config = load_config()
    command = config["recording"]["command"]

    recording_process = start_process(command)

    return {
        "ok": True,
        "status": "recording started",
        "pid": recording_process.pid,
    }


@app.post("/recording/stop")
def stop_recording():
    global recording_process

    if not is_alive(recording_process):
        return {
            "ok": True,
            "status": "not recording",
        }

    stop_process(recording_process)
    recording_process = None

    return {
        "ok": True,
        "status": "recording stopped",
    }