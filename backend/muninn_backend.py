#!/usr/bin/env python3

import json
import os
import signal
import subprocess
from pathlib import Path

import yaml
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from datetime import datetime
import time
import threading
import getpass
import shutil

import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, DurabilityPolicy
from std_msgs.msg import String


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
node_monitor_process = None

transfer_state = {
    "active": False,
    "method": None,
    "bag_name": None,
    "source_path": None,
    "destination_path": None,
    "destination_type": None,
    "status": "idle",
    "progress": 0.0,
    "speed": None,
    "current": None,
    "error": None,
}

muninn_status = {}
muninn_status_lock = threading.Lock()

battery_status = {
    "available": False,
    "percentage": None,
}
battery_lock = threading.Lock()

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


def run_bash(command: str, timeout=None):
    return subprocess.check_output(
        ros_shell(command),
        shell=True,
        text=True,
        executable="/bin/bash",
        env=bash_env(),
        timeout=timeout,
    )



class MuninnStatusSubscriber(Node):
    def __init__(self):
        super().__init__("muninn_backend_status_subscriber")

        qos = QoSProfile(depth=10)
        qos.reliability = ReliabilityPolicy.RELIABLE
        qos.durability = DurabilityPolicy.VOLATILE

        self.create_subscription(
            String,
            "/muninn/status",
            self.status_callback,
            qos,
        )

        self.get_logger().info("Muninn backend subscribed to /muninn/status")

    def status_callback(self, msg):
        global muninn_status
        global battery_status

        try:
            status = json.loads(msg.data)
        except json.JSONDecodeError as e:
            self.get_logger().warn(f"Could not decode /muninn/status JSON: {e}")
            return

        battery = status.get("battery")

        if not isinstance(battery, dict):
            battery = {
                "available": False,
                "percentage": None,
            }

        battery = {
            "available": bool(battery.get("available", False)),
            "percentage": battery.get("percentage"),
        }

        with muninn_status_lock:
            muninn_status = status

        with battery_lock:
            battery_status = battery



def start_node_monitor_process():
    global node_monitor_process

    # Do not start a duplicate if the backend already owns a running one.
    if is_alive(node_monitor_process):
        return

    # If node_monitor is already running outside the backend, leave it alone.
    # This keeps manual testing/systemd launch from being duplicated.
    current_nodes = get_ros_nodes()
    if "/muninn_node_monitor" in current_nodes:
        return

    node_monitor_process = start_process("ros2 run muninn_ros node_monitor")
    processes["node_monitor"] = node_monitor_process

def start_network_monitor_process():
    if "network_monitor" in processes and is_alive(processes["network_monitor"]):
        return True

    current_nodes = get_ros_nodes()

    if "/muninn_network_monitor" in current_nodes:
        return True

    process = start_process("ros2 run muninn_ros network_monitor")
    processes["network_monitor"] = process
    return True


def ros_spin_thread():
    try:
        if not rclpy.ok():
            rclpy.init()

        node = MuninnStatusSubscriber()
        rclpy.spin(node)

    except Exception as e:
        print(f"[Muninn Backend] ROS status subscriber failed: {e}")


@app.on_event("startup")
def start_ros_workers():
    start_node_monitor_process()
    start_network_monitor_process()

    ros_thread = threading.Thread(
        target=ros_spin_thread,
        daemon=True,
    )
    ros_thread.start()


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


# Storage helper functions
def build_disk_usage(path: Path):
    try:
        usage = shutil.disk_usage(path)
        total = usage.total
        used = usage.used
        free = usage.free

        used_percent = round((used / total) * 100.0, 1) if total > 0 else 0.0
        free_percent = round((free / total) * 100.0, 1) if total > 0 else 0.0

        return {
            "path": str(path),
            "available": True,
            "total_bytes": total,
            "used_bytes": used,
            "free_bytes": free,
            "total_gb": round(total / (1024 ** 3), 2),
            "used_gb": round(used / (1024 ** 3), 2),
            "free_gb": round(free / (1024 ** 3), 2),
            "used_percent": used_percent,
            "free_percent": free_percent,
        }
    except Exception as e:
        return {
            "path": str(path),
            "available": False,
            "error": str(e),
        }


def build_storage_status(config, usb_status):
    bags_dir = get_bags_directory(config)

    storage = {
        "bags": build_disk_usage(bags_dir),
        "usb": None,
    }

    selected_mount = usb_status.get("selected_mount")

    if selected_mount:
        storage["usb"] = build_disk_usage(Path(selected_mount["path"]))

    return storage


# USB helper functions
def can_write_to_path(path: Path) -> bool:
    test_file = path / ".muninn_write_test"

    try:
        test_file.write_text("test")
        test_file.unlink()
        return True
    except Exception:
        return False


def get_usb_mounts():
    user = getpass.getuser()

    candidates = [
        Path(f"/media/{user}"),
        Path(f"/run/media/{user}"),
    ]

    mounts = []

    for base in candidates:
        if not base.exists():
            continue

        for item in base.iterdir():
            if not item.is_dir():
                continue

            mounts.append({
                "name": item.name,
                "path": str(item),
                "writable": can_write_to_path(item),
            })

    return mounts


def get_first_writable_usb_mount():
    for mount in get_usb_mounts():
        if mount.get("writable") is True:
            return Path(mount["path"])

    return None


def build_usb_status():
    mounts = get_usb_mounts()
    writable_mounts = [
        mount for mount in mounts
        if mount.get("writable") is True
    ]

    return {
        "connected": len(mounts) > 0,
        "writable": len(writable_mounts) > 0,
        "mounts": mounts,
        "selected_mount": writable_mounts[0] if writable_mounts else None,
    }

def run_rsync_transfer(
    source: Path,
    destination_parent: Path,
    method: str,
    destination_type: str = "local",
):
    global transfer_state

    try:
        transfer_state["method"] = method
        transfer_state["destination_type"] = destination_type
        transfer_state["status"] = "transferring"
        transfer_state["progress"] = 0.0
        transfer_state["speed"] = None
        transfer_state["current"] = "Starting transfer"
        transfer_state["error"] = None

        destination_parent.mkdir(parents=True, exist_ok=True)

        total_size = folder_size_bytes(source)
        destination_path = destination_parent / source.name

        cmd = [
            "rsync",
            "-a",
            "--delete",
            str(source),
            str(destination_parent),
        ]

        process = subprocess.Popen(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )

        while process.poll() is None:
            copied_size = folder_size_bytes(destination_path)

            if total_size > 0:
                progress = min((copied_size / total_size) * 100.0, 99.0)
            else:
                progress = 0.0

            transfer_state["progress"] = progress
            transfer_state["current"] = "Copying files"

            time.sleep(0.5)

        _, stderr = process.communicate()

        if process.returncode != 0:
            transfer_state["status"] = "failed"
            transfer_state["error"] = stderr
            return

        transfer_state["status"] = "finalizing"
        transfer_state["progress"] = 100.0
        transfer_state["current"] = "Finalizing transfer"

        subprocess.run(["sync"], check=False)

        transfer_state["status"] = "completed"
        transfer_state["progress"] = 100.0
        transfer_state["current"] = "Transfer completed"
        transfer_state["error"] = None

    except Exception as e:
        transfer_state["status"] = "failed"
        transfer_state["error"] = str(e)

    finally:
        transfer_state["active"] = False

@app.get("/bags")
def bags():
    config = load_config()
    
    return {
        "ok": True,
        "bags_directory": str(get_bags_directory(config)),
        "bags": list_bags_from_disk(config),
    }
    
@app.delete("/bags/{bag_name}")
def delete_bag(bag_name: str):
    if is_alive(recording_process):
        return {
            "ok": False,
            "error": "Cannot delete while recording",
        }

    if transfer_state["active"]:
        return {
            "ok": False,
            "error": "Cannot delete while transfer is active",
        }

    config = load_config()
    bags_dir = get_bags_directory(config)
    bag_path = bags_dir / bag_name

    if not bag_path.exists() or not bag_path.is_dir():
        return {
            "ok": False,
            "error": f"Bag not found: {bag_name}",
        }

    if bag_path.parent.resolve() != bags_dir.resolve():
        return {
            "ok": False,
            "error": "Invalid bag path",
        }

    try:
        shutil.rmtree(bag_path)
        return {
            "ok": True,
            "status": "Bag deleted",
            "bag_name": bag_name,
        }
    except Exception as e:
        return {
            "ok": False,
            "error": str(e),
        }

@app.get("/usb")
def usb_status():
    usb = build_usb_status()

    return {
        "ok": True,
        **usb,
    }

@app.post("/bags/transfer/usb/{bag_name}")
def transfer_bag_to_usb(bag_name: str):
    global transfer_state

    if is_alive(recording_process):
        return {
            "ok": False,
            "error": "Cannot transfer while recording",
        }

    if transfer_state["active"]:
        return {
            "ok": False,
            "error": "Transfer already active",
        }

    config = load_config()
    bags_dir = get_bags_directory(config)
    bag_path = bags_dir / bag_name

    if not bag_path.exists() or not bag_path.is_dir():
        return {
            "ok": False,
            "error": f"Bag not found: {bag_name}",
        }

    usb_path = get_first_writable_usb_mount()

    if usb_path is None:
        return {
            "ok": False,
            "error": "No writable USB drive detected",
        }

    destination_parent = usb_path / "muninn_bags"
    destination_path = destination_parent / bag_name

    transfer_state = {
        "active": True,
        "method": None,
        "destination_type": "local",
        "bag_name": bag_name,
        "source_path": str(bag_path),
        "destination_path": str(destination_path),
        "status": "preparing",
        "progress": 0.0,
        "speed": None,
        "current": "Preparing transfer",
        "error": None,
    }

    thread = threading.Thread(
        target=run_rsync_transfer,
        args=(
            bag_path,
            destination_parent,
            "usb",
            "local",
        ),
        daemon=True,
    )
    thread.start()

    usb = build_usb_status()

    return {
        "ok": True,
        "status": "USB transfer started",
        "transfer": transfer_state,
        "usb": usb,
    }

@app.get("/status")
def status():
    config = load_config()
    current_nodes = get_ros_nodes()

    sensor_status = build_sensor_status(config, current_nodes)
    status_only = build_status_only(config, current_nodes)
    camera_rtk = managed_camera_rtk_status(config, sensor_status)
    usb = build_usb_status()
    storage = build_storage_status(config, usb)

    with battery_lock:
        battery = dict(battery_status)

    with muninn_status_lock:
        diagnostics = dict(muninn_status)

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
        "transfer": transfer_state,
        "usb": usb,
        "storage": storage,
        "battery": battery,
        "diagnostics": diagnostics,
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