#!/usr/bin/env python3

import os
import signal
import subprocess
from pathlib import Path

import yaml
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime
import time
import shutil


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
current_bag_name = None
current_bag_path = None
recording_start_time = None
last_completed_bag_name = None
last_completed_bag_path = None

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


def get_ros_nodes():
    try:
        output = run_bash("ros2 node list")
        return [line.strip() for line in output.splitlines() if line.strip()]
    except Exception:
        return []


def build_sensor_status(config, current_nodes):
    sensor_status = {}

    for key, sensor_cfg in config.get("sensors", {}).items():
        expected_node = sensor_cfg.get("ros_node_name")
        running = expected_node in current_nodes if expected_node else False

        sensor_status[key] = {
            "display_name": sensor_cfg.get("display_name", key),
            "ros_node_name": expected_node,
            "running": running,
            "launched_by_backend": key in processes and is_alive(processes[key]),
            "launchable": sensor_cfg.get("launchable", True),
        }

    return sensor_status


def build_status_only(config, current_nodes):
    status_only = {}

    for key, node_cfg in config.get("status_only", {}).items():
        expected_node = node_cfg.get("ros_node_name")
        running = expected_node in current_nodes if expected_node else False

        status_only[key] = {
            "display_name": node_cfg.get("display_name", key),
            "ros_node_name": expected_node,
            "running": running,
        }

    return status_only


def managed_camera_rtk_status(config, sensor_status):
    managed = config.get("all_sensors", {}).get("managed_sensors", [])

    running_count = sum(
        1
        for key in managed
        if sensor_status.get(key, {}).get("running") is True
    )

    total_count = len(managed)

    return {
        "running": total_count > 0 and running_count == total_count,
        "running_count": running_count,
        "total_count": total_count,
    }


@app.get("/")
def root():
    return {
        "ok": True,
        "name": "Muninn Backend",
        "docs": "/docs",
    }


@app.get("/nodes")
def list_ros_nodes():
    nodes = get_ros_nodes()

    return {
        "ok": True,
        "nodes": nodes,
    }

def get_bags_directory(config):
    return Path(
        config["recording"].get(
            "bags_directory",
            "~/ros2_ws/src/muninn_ros/bags",
        )
    ).expanduser()


def folder_size_bytes(path: Path) -> int:
    total = 0

    for item in path.rglob("*"):
        if item.is_file():
            try:
                total += item.stat().st_size
            except OSError:
                pass

    return total


def list_bags_from_disk(config):
    bags_dir = get_bags_directory(config)

    if not bags_dir.exists():
        return []

    bag_dirs = [
        path for path in bags_dir.iterdir()
        if path.is_dir()
    ]

    bag_dirs.sort(
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )

    bags = []

    for index, bag_dir in enumerate(bag_dirs):
        stat = bag_dir.stat()
        size_bytes = folder_size_bytes(bag_dir)

        bags.append({
            "name": bag_dir.name,
            "path": str(bag_dir),
            "size_bytes": size_bytes,
            "size_gb": round(size_bytes / (1024 ** 3), 3),
            "modified": datetime.fromtimestamp(
                stat.st_mtime
            ).strftime("%Y-%m-%d %H:%M:%S"),
            "latest": index == 0,
            "recording": bag_dir.name == current_bag_name,
            "transfer_allowed": bag_dir.name != current_bag_name,
        })

    return bags

@app.get("/bags")
def bags():
    config = load_config()

    return {
        "ok": True,
        "bags_directory": str(get_bags_directory(config)),
        "bags": list_bags_from_disk(config),
    }

@app.get("/status")
def status():
    config = load_config()
    current_nodes = get_ros_nodes()

    sensor_status = build_sensor_status(config, current_nodes)
    status_only = build_status_only(config, current_nodes)
    camera_rtk = managed_camera_rtk_status(config, sensor_status)

    return {
        "ok": True,
        "ros_nodes_visible": current_nodes,

        # Launch group status is based on Camera + Ublox + NTRIP actually running,
        # not only on whether the sensors.launch.py process is alive.
        "camera_rtk_running": camera_rtk["running"],
        "camera_rtk_running_count": camera_rtk["running_count"],
        "camera_rtk_total_count": camera_rtk["total_count"],

        # For debugging only: whether backend still owns the combined launch process.
        "all_sensors_launch_process_running": (
            "all_sensors" in processes and is_alive(processes["all_sensors"])
        ),

        "sensors": sensor_status,
        "status_only": status_only,
        "recording": is_alive(recording_process),
        "current_bag_name": current_bag_name,
        "current_bag_path": current_bag_path,
        "recording_start_time": recording_start_time,
        "last_completed_bag_name": last_completed_bag_name,
        "last_completed_bag_path": last_completed_bag_path,
    }


@app.post("/sensors/start")
def start_all_sensors():
    config = load_config()
    current_nodes = get_ros_nodes()

    sensor_status = build_sensor_status(config, current_nodes)
    camera_rtk = managed_camera_rtk_status(config, sensor_status)

    if camera_rtk["running"]:
        return {
            "ok": True,
            "status": "camera and RTK nodes already running",
            "camera_rtk_running": True,
        }

    key = "all_sensors"

    if key in processes and is_alive(processes[key]):
        return {
            "ok": True,
            "status": "launch process already running",
            "camera_rtk_running": False,
        }

    command = config["all_sensors"]["launch_command"]
    process = start_process(command)
    processes[key] = process

    return {
        "ok": True,
        "status": "camera and RTK launch started",
        "pid": process.pid,
    }


@app.post("/sensors/stop")
def stop_all_sensors():
    config = load_config()

    stopped_launch_process = False

    if "all_sensors" in processes and is_alive(processes["all_sensors"]):
        stop_process(processes["all_sensors"])
        processes.pop("all_sensors", None)
        stopped_launch_process = True

    killed_sensors = []

    for sensor_key in config.get("all_sensors", {}).get("managed_sensors", []):
        sensor_cfg = config["sensors"].get(sensor_key, {})
        stop_command = sensor_cfg.get("stop_command")

        if stop_command:
            try:
                run_bash(stop_command)
                killed_sensors.append(sensor_key)
            except subprocess.CalledProcessError:
                pass

    return {
        "ok": True,
        "status": "camera and RTK stop requested",
        "stopped_launch_process": stopped_launch_process,
        "killed_sensors": killed_sensors,
    }


@app.post("/sensor/{sensor_key}/start")
def start_sensor(sensor_key: str):
    config = load_config()

    if sensor_key not in config["sensors"]:
        return {
            "ok": False,
            "error": f"Unknown sensor: {sensor_key}",
        }

    sensor_cfg = config["sensors"][sensor_key]

    if sensor_cfg.get("launchable", True) is not True:
        return {
            "ok": False,
            "error": f"Sensor is status-only and cannot be launched: {sensor_key}",
        }

    current_nodes = get_ros_nodes()
    expected_node = sensor_cfg.get("ros_node_name")

    if expected_node and expected_node in current_nodes:
        return {
            "ok": True,
            "status": "sensor node already running",
            "sensor": sensor_key,
        }

    if sensor_key in processes and is_alive(processes[sensor_key]):
        return {
            "ok": True,
            "status": "sensor already launched by backend",
            "sensor": sensor_key,
        }

    command = sensor_cfg.get("launch_command")

    if not command:
        return {
            "ok": False,
            "error": f"No launch command configured for sensor: {sensor_key}",
        }

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
    config = load_config()

    if sensor_key not in config["sensors"]:
        return {
            "ok": False,
            "error": f"Unknown sensor: {sensor_key}",
        }

    stopped_backend_process = False
    ran_stop_command = False

    if sensor_key in processes and is_alive(processes[sensor_key]):
        stop_process(processes[sensor_key])
        processes.pop(sensor_key, None)
        stopped_backend_process = True

    stop_command = config["sensors"][sensor_key].get("stop_command")

    if stop_command:
        try:
            run_bash(stop_command)
            ran_stop_command = True
        except subprocess.CalledProcessError:
            # pkill returns non-zero if no process matched.
            ran_stop_command = False

    return {
        "ok": True,
        "status": "sensor stop requested",
        "sensor": sensor_key,
        "stopped_backend_process": stopped_backend_process,
        "ran_stop_command": ran_stop_command,
    }


@app.post("/recording/start")
def start_recording():
    global recording_process
    global current_bag_name
    global current_bag_path
    global recording_start_time

    if is_alive(recording_process):
        return {
            "ok": True,
            "status": "already recording",
            "current_bag_name": current_bag_name,
            "current_bag_path": current_bag_path,
        }

    config = load_config()

    bags_dir = Path(
        config["recording"].get(
            "bags_directory",
            "~/ros2_ws/src/muninn_ros/bags",
        )
    ).expanduser()

    current_bag_name = f"husky_sensor_bag_{datetime.now():%Y%m%d_%H%M%S}"
    current_bag_path = str(bags_dir / current_bag_name)
    recording_start_time = time.time()

    command = f'{config["recording"]["command"]} "{current_bag_name}"'

    recording_process = start_process(command)

    return {
        "ok": True,
        "status": "recording started",
        "pid": recording_process.pid,
        "current_bag_name": current_bag_name,
        "current_bag_path": current_bag_path,
        "recording_start_time": recording_start_time,
    }

@app.post("/recording/stop")
def stop_recording():
    global recording_process
    global current_bag_name
    global current_bag_path
    global recording_start_time
    global last_completed_bag_name
    global last_completed_bag_path

    if not is_alive(recording_process):
        return {
            "ok": True,
            "status": "not recording",
            "last_completed_bag_name": last_completed_bag_name,
            "last_completed_bag_path": last_completed_bag_path,
        }

    stop_process(recording_process)
    recording_process = None

    last_completed_bag_name = current_bag_name
    last_completed_bag_path = current_bag_path

    current_bag_name = None
    current_bag_path = None
    recording_start_time = None

    return {
        "ok": True,
        "status": "recording stopped",
        "last_completed_bag_name": last_completed_bag_name,
        "last_completed_bag_path": last_completed_bag_path,
    }