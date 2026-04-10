#!/data/data/com.termux/files/usr/bin/bash
pkg update -y && pkg upgrade -y
pkg install -y python rust binutils cmake make clang openssl-tool wget curl termux-api android-tools
pip install --upgrade pip
pip install flask flask-socketio pyngrok pillow mss numpy opencv-python pyautogui websockets asyncio aiohttp
mkdir -p ~/remote_access_server
cat > ~/remote_access_server/server.py << 'EOF'
import os
import sys
import subprocess
import socket
import threading
import json
import base64
import time
import asyncio
import websockets
from flask import Flask, send_file, request, jsonify, render_template_string
from flask_socketio import SocketIO, emit
import mss
import numpy as np
from PIL import Image
import io
import pyautogui
import warnings
warnings.filterwarnings("ignore")

app = Flask(__name__)
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='threading')
pyautogui.FAILSAFE = False
pyautogui.PAUSE = 0

HTML_TEMPLATE = '''
<!DOCTYPE html>
<html>
<head>
    <title>Remote Control</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { background: #0a0a0a; font-family: monospace; color: #0f0; }
        #screen { width: 100%; max-width: 100%; cursor: crosshair; border: 2px solid #0f0; }
        #controls { padding: 10px; background: #111; display: flex; flex-wrap: wrap; gap: 5px; }
        button { padding: 10px 20px; background: #1a1a1a; color: #0f0; border: 1px solid #0f0; cursor: pointer; font-weight: bold; }
        button:hover { background: #0f0; color: #000; }
        input { padding: 10px; background: #1a1a1a; color: #0f0; border: 1px solid #0f0; flex: 1; }
        #status { padding: 5px; color: #ff0; }
        #shellout { background: #000; padding: 10px; height: 200px; overflow-y: scroll; font-size: 12px; white-space: pre-wrap; }
        .cmdline { display: flex; gap: 5px; margin-top: 5px; }
    </style>
</head>
<body>
    <div id="status">Connecting...</div>
    <img id="screen" draggable="false">
    <div id="controls">
        <button onclick="sendKey('home')">HOME</button>
        <button onclick="sendKey('back')">BACK</button>
        <button onclick="sendKey('app_switch')">RECENTS</button>
        <button onclick="sendKey('volume_up')">VOL+</button>
        <button onclick="sendKey('volume_down')">VOL-</button>
        <button onclick="sendKey('power')">POWER</button>
        <button onclick="toggleStream()">TOGGLE STREAM</button>
        <button onclick="sendShell()">SEND CMD</button>
    </div>
    <div id="shellout"></div>
    <div class="cmdline">
        <input type="text" id="cmd" placeholder="shell command" value="ls -la /sdcard">
        <button onclick="sendShell()">Execute</button>
    </div>
    <script src="https://cdn.socket.io/4.5.0/socket.io.min.js"></script>
    <script>
        const socket = io();
        const screen = document.getElementById('screen');
        const status = document.getElementById('status');
        const shellout = document.getElementById('shellout');
        let streaming = true;
        let screenW = 1080, screenH = 2400;
        
        socket.on('connect', () => status.innerText = 'Connected');
        socket.on('disconnect', () => status.innerText = 'Disconnected');
        socket.on('frame', data => { if(streaming) screen.src = 'data:image/jpeg;base64,' + data; });
        socket.on('shell_result', data => shellout.innerText = data);
        socket.on('screen_size', data => { screenW = data.w; screenH = data.h; });
        
        screen.onmousedown = e => {
            const rect = screen.getBoundingClientRect();
            const x = Math.round((e.clientX - rect.left) * screenW / rect.width);
            const y = Math.round((e.clientY - rect.top) * screenH / rect.height);
            socket.emit('touch', {action: 'down', x, y});
        };
        screen.onmouseup = e => {
            const rect = screen.getBoundingClientRect();
            const x = Math.round((e.clientX - rect.left) * screenW / rect.width);
            const y = Math.round((e.clientY - rect.top) * screenH / rect.height);
            socket.emit('touch', {action: 'up', x, y});
        };
        screen.onmousemove = e => {
            if(e.buttons !== 1) return;
            const rect = screen.getBoundingClientRect();
            const x = Math.round((e.clientX - rect.left) * screenW / rect.width);
            const y = Math.round((e.clientY - rect.top) * screenH / rect.height);
            socket.emit('touch', {action: 'move', x, y});
        };
        screen.oncontextmenu = e => e.preventDefault();
        
        function sendKey(k) { socket.emit('key', k); }
        function toggleStream() { streaming = !streaming; }
        function sendShell() {
            const cmd = document.getElementById('cmd').value;
            socket.emit('shell', cmd);
        }
        document.getElementById('cmd').onkeypress = e => { if(e.key==='Enter') sendShell(); };
    </script>
</body>
</html>
'''

def get_shizuku_path():
    paths = [
        '/storage/emulated/0/Shizuku',
        '/sdcard/Shizuku',
        '/storage/emulated/0/Android/data/moe.shizuku.privileged.api/files'
    ]
    for p in paths:
        if os.path.exists(p): return p
    return None

def shizuku_exec(cmd):
    shizuku_path = get_shizuku_path()
    if not shizuku_path: return "Shizuku not found"
    sh_file = f"{shizuku_path}/shizuku"
    if os.path.exists(sh_file):
        result = subprocess.run([sh_file, 'shell', cmd], capture_output=True, text=True, timeout=10)
        return result.stdout + result.stderr
    return "Shizuku binary not accessible"

def adb_exec(cmd):
    try:
        result = subprocess.run(['adb', 'shell', cmd], capture_output=True, text=True, timeout=10)
        return result.stdout + result.stderr
    except: return shizuku_exec(cmd)

def execute_command(cmd):
    try:
        if 'screencap' in cmd or 'input' in cmd:
            return adb_exec(cmd)
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30, executable='/data/data/com.termux/files/usr/bin/bash')
        return result.stdout + result.stderr
    except Exception as e:
        return str(e)

def capture_screen():
    try:
        with mss.mss() as sct:
            monitor = sct.monitors[1]
            img = sct.grab(monitor)
            pil_img = Image.frombytes('RGB', img.size, img.bgra, 'raw', 'BGRX')
            pil_img = pil_img.resize((int(pil_img.width*0.5), int(pil_img.height*0.5)), Image.LANCZOS)
            buffer = io.BytesIO()
            pil_img.save(buffer, format='JPEG', quality=40)
            return base64.b64encode(buffer.getvalue()).decode()
    except:
        try:
            result = subprocess.run(['screencap', '-p'], capture_output=True, timeout=3)
            return base64.b64encode(result.stdout).decode()
        except: return ''

def get_screen_size():
    try:
        with mss.mss() as sct:
            m = sct.monitors[1]
            return m['width'], m['height']
    except: return 1080, 2400

def perform_touch(action, x, y):
    cmd = f"input {action} {x} {y}"
    if action == 'move': cmd = f"input motionevent {action.upper()} {x} {y}"
    adb_exec(cmd)

def perform_key(key):
    key_map = {
        'home': 'KEYCODE_HOME', 'back': 'KEYCODE_BACK', 'app_switch': 'KEYCODE_APP_SWITCH',
        'volume_up': 'KEYCODE_VOLUME_UP', 'volume_down': 'KEYCODE_VOLUME_DOWN', 'power': 'KEYCODE_POWER'
    }
    keycode = key_map.get(key, key)
    adb_exec(f"input keyevent {keycode}")

@socketio.on('connect')
def handle_connect():
    w, h = get_screen_size()
    emit('screen_size', {'w': w, 'h': h})

@socketio.on('touch')
def handle_touch(data):
    perform_touch(data['action'], data['x'], data['y'])

@socketio.on('key')
def handle_key(data):
    perform_key(data)

@socketio.on('shell')
def handle_shell(cmd):
    result = execute_command(cmd)
    emit('shell_result', result)

def stream_frames():
    while True:
        if socketio.server.manager.rooms.get('/', {}):
            frame = capture_screen()
            if frame: socketio.emit('frame', frame)
        time.sleep(0.05)

@app.route('/')
def index():
    return render_template_string(HTML_TEMPLATE)

def start_server():
    socketio.start_background_task(stream_frames)
    socketio.run(app, host='0.0.0.0', port=5000, allow_unsafe_werkzeug=True)

if __name__ == '__main__':
    start_server()
EOF

cat > ~/remote_access_server/auto_setup.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
IP=$(ip route get 1 | awk '{print $NF;exit}')
if [ -z "$IP" ]; then IP=$(ifconfig wlan0 | grep 'inet ' | awk '{print $2}'); fi
if [ -z "$IP" ]; then IP="127.0.0.1"; fi
echo "Server starting on http://$IP:5000"
cd ~/remote_access_server
python server.py
EOF

chmod +x ~/remote_access_server/auto_setup.sh

cat > ~/remote_access_server/shizuku_bridge.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
SHIZUKU_DIR="/storage/emulated/0/Shizuku"
if [ ! -f "$SHIZUKU_DIR/shizuku" ]; then
    echo "Shizuku binary not found. Place shizuku binary in $SHIZUKU_DIR"
    exit 1
fi
export PATH=$PATH:$SHIZUKU_DIR
alias adb="$SHIZUKU_DIR/shizuku shell"
cd ~/remote_access_server
python server.py
EOF

chmod +x ~/remote_access_server/shizuku_bridge.sh

cat > ~/.termux/termux.properties << 'EOF'
allow-external-apps = true
volume-keys = volume
extra-keys = [[ESC, TAB, CTRL, ALT, {key: '-', popup: '|'}, DOWN, UP]]
use-black-ui = true
bell-character = ignore
EOF

termux-reload-settings

echo "======================================"
echo "REMOTE ACCESS SERVER SETUP COMPLETE"
echo "======================================"
echo "Gateway IP: $(ip route get 1 | awk '{print $NF;exit}' || ifconfig wlan0 | grep 'inet ' | awk '{print $2}')"
echo ""
echo "Run server with: ~/remote_access_server/auto_setup.sh"
echo "Or with Shizuku: ~/remote_access_server/shizuku_bridge.sh"
echo ""
echo "Connect from other device: http://GATEWAY_IP:5000"
echo "======================================"
