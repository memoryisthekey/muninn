#!/usr/bin/env python3

import os
import signal
import subprocess
from pathlib import Path
from datetime import datetime

import yaml
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware


CONFIG_FILE = Path("robot_backend_config.yaml")

app = FastAPI(title="Robot Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

launched_processes = {}
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


def run_bash(command: str):
    full_command = f"""
    source /opt/ros/jazzy/setup.bash
    source ~/ros2_ws/install/setup.bash
    {command}
    """

    return subprocess.check_output(
        full_command,
        shell=True,
        text=True,
        executable="/bin/bash",
        env=bash_env(),
    )


def start_bash_process(command: str):
    full_command = f"""
    source /opt/ros/jazzy/setup.bash
    source ~/ros2_ws/install/setup.bash
    {command}
    """

    return subprocess.Popen(
        full_command,
        shell=True,
        executable="/bin/bash",
        env=bash_env(),
        preexec_fn=os.setsid,
    )


def is_process_alive(process):
    return process is not None and process.poll() is None


def stop_process(process):
    if not is_process_alive(process):
        return False

    os.killpg(os.getpgid(process.pid), signal.SIGINT)
    process.wait(timeout=10)
    return True


@app.get("/")
def root():
    return {
        "status": "robot backend running",
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
        current_nodes = [
            line.strip()
            for line in output.splitlines()
            if line.strip()
        ]
    except Exception:
        current_nodes = []

    required_nodes = []

    for key, node_cfg in config["nodes"].items():
        expected_node = node_cfg["ros_node_name"]

        required_nodes.append({
            "key": key,
            "display_name": node_cfg.get("display_name", key),
            "ros_node_name": expected_node,
            "running": expected_node in current_nodes,
            "launched_by_backend": (
                key in launched_processes
                and is_process_alive(launched_processes[key])
            ),
        })

    return {
        "ros_nodes_visible": current_nodes,
        "required_nodes": required_nodes,
        "recording": is_process_alive(recording_process),
    }


@app.post("/launch/{node_key}")
def launch_node(node_key: str):
    config = load_config()

    if node_key not in config["nodes"]:
        return {
            "ok": False,
            "error": f"Unknown node key: {node_key}",
        }

    if (
        node_key in launched_processes
        and is_process_alive(launched_processes[node_key])
    ):
        return {
            "ok": True,
            "status": "already launched by backend",
        }

    command = config["nodes"][node_key]["launch_command"]

    process = start_bash_process(command)
    launched_processes[node_key] = process

    return {
        "ok": True,
        "status": "launched",
        "node_key": node_key,
        "pid": process.pid,
    }


@app.post("/stop/{node_key}")
def stop_node(node_key: str):
    if node_key not in launched_processes:
        return {
            "ok": False,
            "error": "This node was not launched by the backend",
        }

    process = launched_processes[node_key]

    try:
        stopped = stop_process(process)
        return {
            "ok": True,
            "stopped": stopped,
            "node_key": node_key,
        }
    except Exception as e:
        return {
            "ok": False,
            "error": str(e),
        }


@app.post("/record/start")
def start_recording():
    global recording_process

    if is_process_alive(recording_process):
        return {
            "ok": True,
            "status": "already recording",
        }

    config = load_config()
    recording_cfg = config["recording"]

    output_dir = Path(recording_cfg["output_dir"]).expanduser()
    output_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    bag_path = output_dir / f"bag_{timestamp}"

    topics = " ".join(recording_cfg["topics"])

    command = f"ros2 bag record {topics} -o {bag_path}"

    recording_process = start_bash_process(command)

    return {
        "ok": True,
        "status": "recording started",
        "bag_path": str(bag_path),
        "pid": recording_process.pid,
    }


@app.post("/record/stop")
def stop_recording():
    global recording_process

    if not is_process_alive(recording_process):
        return {
            "ok": True,
            "status": "not recording",
        }

    try:
        stop_process(recording_process)
        recording_process = None

        return {
            "ok": True,
            "status": "recording stopped",
        }
    except Exception as e:
        return {
            "ok": False,
            "error": str(e),
        }