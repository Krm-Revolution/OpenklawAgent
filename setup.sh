#!/data/data/com.termux/files/usr/bin/bash

set -e

export DEBIAN_FRONTEND=noninteractive
export LANG=C
export LC_ALL=C

clear
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "                    🔥 PHONE GATEWAY CONTROLLER v3.0 🔥"
echo "                         Non-Root | Shizuku | WiFi Remote"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

pkill -f "node.*gateway" 2>/dev/null || true
pkill -f "http-server" 2>/dev/null || true

echo "[1/6] 📦 Installing system packages..."
pkg update -y 2>&1 | grep -E "(Reading|Building|Get:|Unpacking)" || true
pkg install -y nodejs git curl jq termux-api openssh nmap 2>&1 | grep -E "(Setting up|Unpacking)" || true
echo "✓ Packages installed"
echo ""

echo "[2/6] 📁 Creating project structure..."
rm -rf ~/phonegate 2>/dev/null || true
mkdir -p ~/phonegate/{web,data}
cd ~/phonegate
echo "✓ Folders created: ~/phonegate"
echo ""

echo "[3/6] 📲 Setting up Shizuku integration..."
termux-setup-storage 2>/dev/null || true
sleep 1

SHIZUKU_DIR="$HOME/storage/shared/Android/data/moe.shizuku.privileged.api/start_files"
mkdir -p "$SHIZUKU_DIR" 2>/dev/null || true

cat > ~/phonegate/shizuku_setup.sh << 'SHIZUKU_END'
#!/data/data/com.termux/files/usr/bin/bash
BIN=/data/data/com.termux/files/usr/bin
HOME=/data/data/com.termux/files/home
cat > "${BIN}/rish" << 'RISH_END'
#!/data/data/com.termux/files/usr/bin/bash
[ -z "$RISH_APPLICATION_ID" ] && export RISH_APPLICATION_ID="com.termux"
DEX="$HOME/rish_shizuku.dex"
if [ ! -f "$DEX" ]; then
    echo "ERROR: rish_shizuku.dex not found. Please export from Shizuku app first."
    exit 1
fi
exec /system/bin/app_process -Djava.class.path="$DEX" /system/bin --nice-name=rish rikka.shizuku.shell.ShizukuShellLoader "$@"
RISH_END
chmod +x "${BIN}/rish"
echo "✓ Shizuku commands installed"
SHIZUKU_END

chmod +x ~/phonegate/shizuku_setup.sh
bash ~/phonegate/shizuku_setup.sh
echo "✓ Shizuku ready (remember to export files from Shizuku app)"
echo ""

echo "[4/6] 🎮 Creating phone controller..."
cat > ~/phonegate/control.sh << 'CONTROL_END'
#!/data/data/com.termux/files/usr/bin/bash
exec_cmd() {
    if command -v rish &>/dev/null; then
        rish -c "$1" 2>&1
    else
        echo "ERROR: Shizuku not configured. Export files from Shizuku app and restart."
        return 1
    fi
}

case "$1" in
    tap) exec_cmd "input tap $2 $3" ;;
    swipe) exec_cmd "input swipe $2 $3 $4 $5 ${6:-300}" ;;
    text) exec_cmd "input text '${2// /%s}'" ;;
    key) exec_cmd "input keyevent $2" ;;
    home) exec_cmd "input keyevent 3" ;;
    back) exec_cmd "input keyevent 4" ;;
    recent) exec_cmd "input keyevent 187" ;;
    power) exec_cmd "input keyevent 26" ;;
    volup) exec_cmd "input keyevent 24" ;;
    voldown) exec_cmd "input keyevent 25" ;;
    screenshot) exec_cmd "screencap -p /sdcard/screenshot.png" && echo "/sdcard/screenshot.png" ;;
    openapp) exec_cmd "monkey -p $2 1" ;;
    openurl) exec_cmd "am start -a android.intent.action.VIEW -d '$2'" ;;
    battery) exec_cmd "dumpsys battery" | grep -E "level|status|temperature" ;;
    brightness) exec_cmd "settings put system screen_brightness $2" ;;
    volume) exec_cmd "media volume --set $2" ;;
    wifi_on) exec_cmd "svc wifi enable" ;;
    wifi_off) exec_cmd "svc wifi disable" ;;
    bluetooth_on) exec_cmd "cmd bluetooth_manager enable" ;;
    bluetooth_off) exec_cmd "cmd bluetooth_manager disable" ;;
    location_on) exec_cmd "settings put secure location_mode 3" ;;
    location_off) exec_cmd "settings put secure location_mode 0" ;;
    flashlight_on) exec_cmd "cmd flashlight enable" ;;
    flashlight_off) exec_cmd "cmd flashlight disable" ;;
    notify) exec_cmd "cmd notification post -S bigtext -t '$2' 'Gateway' '$3'" ;;
    vibrate) exec_cmd "cmd vibrator vibrate ${2:-500}" ;;
    clipboard) exec_cmd "cmd clipboard get-text" ;;
    applist) exec_cmd "pm list packages -3" | sed 's/package://g' ;;
    info) exec_cmd "getprop ro.product.model && getprop ro.build.version.release" ;;
    ui) exec_cmd "uiautomator dump /sdcard/ui.xml && cat /sdcard/ui.xml" ;;
    shell) exec_cmd "$2" ;;
    *) echo "Unknown: $1" ;;
esac
CONTROL_END

chmod +x ~/phonegate/control.sh
echo "✓ Controller created with 25+ commands"
echo ""

echo "[5/6] 🚀 Creating gateway server..."
cat > ~/phonegate/server.js << 'SERVER_END'
const http = require('http');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

const PORT = process.env.PORT || 3000;
const controlScript = path.join(__dirname, 'control.sh');

const mimeTypes = {
    '.html': 'text/html',
    '.css': 'text/css',
    '.js': 'text/javascript',
    '.json': 'application/json'
};

function execCommand(cmd, args = '') {
    return new Promise((resolve) => {
        const fullCmd = `bash ${controlScript} ${cmd} ${args}`;
        exec(fullCmd, { timeout: 10000 }, (err, stdout, stderr) => {
            resolve(err ? `Error: ${err.message}` : (stdout || stderr || 'Done'));
        });
    });
}

const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, `http://${req.headers.host}`);
    
    if (url.pathname === '/api/status') {
        const battery = await execCommand('battery');
        const info = await execCommand('info');
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ battery, info, status: 'online' }));
        return;
    }
    
    if (url.pathname === '/api/command') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', async () => {
            const { cmd, args } = JSON.parse(body);
            const result = await execCommand(cmd, args);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ result }));
        });
        return;
    }
    
    if (url.pathname === '/api/commands') {
        const commands = [
            'tap [x] [y]', 'swipe [x1] [y1] [x2] [y2]', 'text [msg]', 'key [code]',
            'home', 'back', 'recent', 'power', 'volup', 'voldown',
            'screenshot', 'openapp [pkg]', 'openurl [url]', 'battery',
            'brightness [0-255]', 'volume [0-15]', 'wifi_on', 'wifi_off',
            'bluetooth_on', 'bluetooth_off', 'location_on', 'location_off',
            'flashlight_on', 'flashlight_off', 'notify [title] [msg]',
            'vibrate [ms]', 'clipboard', 'applist', 'info', 'ui', 'shell [cmd]'
        ];
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ commands }));
        return;
    }
    
    let filePath = path.join(__dirname, 'web', url.pathname === '/' ? 'index.html' : url.pathname);
    
    fs.readFile(filePath, (err, content) => {
        if (err) {
            res.writeHead(404);
            res.end('404 Not Found');
        } else {
            const ext = path.extname(filePath);
            res.writeHead(200, { 'Content-Type': mimeTypes[ext] || 'text/plain' });
            res.end(content);
        }
    });
});

server.listen(PORT, '0.0.0.0', () => {
    exec("ip route get 1 | grep -oP 'src \\K\\S+'", (err, ip) => {
        const address = ip ? ip.trim() : 'localhost';
        console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        console.log('🌐 Gateway Online');
        console.log(`📱 Access URL: http://${address}:${PORT}`);
        console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
        console.log('Enable hotspot and share URL with other devices!');
        console.log('Press Ctrl+C to stop\n');
    });
});
SERVER_END

echo "✓ Server created (Node.js HTTP)"
echo ""

echo "[6/6] 🎨 Creating web interface..."
cat > ~/phonegate/web/index.html << 'HTML_END'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Phone Gateway</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        .header {
            background: rgba(255,255,255,0.95);
            padding: 20px;
            border-radius: 15px;
            margin-bottom: 20px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
        }
        .header h1 {
            font-size: 2em;
            background: linear-gradient(135deg, #667eea, #764ba2);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            margin-bottom: 10px;
        }
        .status {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 20px;
        }
        .status-card {
            background: rgba(255,255,255,0.95);
            padding: 15px;
            border-radius: 10px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        .status-card h3 {
            font-size: 0.9em;
            color: #666;
            margin-bottom: 5px;
        }
        .status-card p {
            font-size: 1.2em;
            font-weight: bold;
            color: #333;
        }
        .panel {
            background: rgba(255,255,255,0.95);
            padding: 20px;
            border-radius: 15px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            margin-bottom: 20px;
        }
        .panel h2 {
            font-size: 1.3em;
            margin-bottom: 15px;
            color: #333;
            border-bottom: 2px solid #667eea;
            padding-bottom: 10px;
        }
        .input-group {
            display: flex;
            gap: 10px;
            margin-bottom: 15px;
        }
        .input-group input {
            flex: 1;
            padding: 12px;
            border: 2px solid #ddd;
            border-radius: 8px;
            font-size: 1em;
        }
        .input-group button, .cmd-btn {
            padding: 12px 24px;
            background: linear-gradient(135deg, #667eea, #764ba2);
            color: white;
            border: none;
            border-radius: 8px;
            font-weight: bold;
            cursor: pointer;
            transition: transform 0.2s;
        }
        .input-group button:hover, .cmd-btn:hover {
            transform: translateY(-2px);
        }
        .cmd-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
            gap: 10px;
            margin-top: 10px;
        }
        .cmd-btn {
            padding: 10px;
            font-size: 0.9em;
        }
        .output {
            background: #1e1e1e;
            color: #0f0;
            padding: 15px;
            border-radius: 8px;
            font-family: monospace;
            min-height: 200px;
            max-height: 400px;
            overflow-y: auto;
            white-space: pre-wrap;
            margin-top: 15px;
        }
        .toast {
            position: fixed;
            bottom: 20px;
            right: 20px;
            background: #333;
            color: white;
            padding: 15px 25px;
            border-radius: 8px;
            animation: slideIn 0.3s ease;
            z-index: 1000;
        }
        @keyframes slideIn {
            from { transform: translateX(100%); }
            to { transform: translateX(0); }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔥 Phone Gateway Controller</h1>
            <p>Remote control your Android device via WiFi</p>
        </div>
        
        <div class="status">
            <div class="status-card">
                <h3>Status</h3>
                <p id="status">Connecting...</p>
            </div>
            <div class="status-card">
                <h3>Device</h3>
                <p id="device">Loading...</p>
            </div>
            <div class="status-card">
                <h3>Battery</h3>
                <p id="battery">--%</p>
            </div>
        </div>
        
        <div class="panel">
            <h2>⚡ Quick Controls</h2>
            <div class="cmd-grid">
                <button class="cmd-btn" onclick="exec('home')">🏠 Home</button>
                <button class="cmd-btn" onclick="exec('back')">⬅️ Back</button>
                <button class="cmd-btn" onclick="exec('recent')">📱 Recent</button>
                <button class="cmd-btn" onclick="exec('power')">⏻ Power</button>
                <button class="cmd-btn" onclick="exec('volup')">🔊 Vol+</button>
                <button class="cmd-btn" onclick="exec('voldown')">🔉 Vol-</button>
                <button class="cmd-btn" onclick="exec('screenshot')">📸 Screen</button>
                <button class="cmd-btn" onclick="exec('wifi_on')">📶 WiFi ON</button>
                <button class="cmd-btn" onclick="exec('wifi_off')">📴 WiFi OFF</button>
                <button class="cmd-btn" onclick="exec('flashlight_on')">💡 Flash</button>
                <button class="cmd-btn" onclick="exec('location_on')">📍 GPS ON</button>
                <button class="cmd-btn" onclick="exec('battery')">🔋 Battery</button>
            </div>
        </div>
        
        <div class="panel">
            <h2>🎮 Advanced Controls</h2>
            <div class="input-group">
                <input type="text" id="tapX" placeholder="X">
                <input type="text" id="tapY" placeholder="Y">
                <button onclick="execTap()">👆 Tap</button>
            </div>
            <div class="input-group">
                <input type="text" id="textInput" placeholder="Text to type">
                <button onclick="execText()">⌨️ Type</button>
            </div>
            <div class="input-group">
                <input type="text" id="urlInput" placeholder="URL">
                <button onclick="execUrl()">🌐 Open URL</button>
            </div>
            <div class="input-group">
                <input type="text" id="customCmd" placeholder="Custom command">
                <button onclick="execCustom()">▶️ Execute</button>
            </div>
        </div>
        
        <div class="panel">
            <h2>📟 Output</h2>
            <div class="output" id="output">Waiting for commands...</div>
        </div>
    </div>
    
    <script>
        const output = document.getElementById('output');
        
        function showToast(msg) {
            const toast = document.createElement('div');
            toast.className = 'toast';
            toast.textContent = msg;
            document.body.appendChild(toast);
            setTimeout(() => toast.remove(), 3000);
        }
        
        function log(msg) {
            output.textContent = msg + '\n' + output.textContent;
        }
        
        async function exec(cmd, args = '') {
            try {
                const res = await fetch('/api/command', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ cmd, args })
                });
                const data = await res.json();
                log(`> ${cmd} ${args}\n${data.result}\n`);
                showToast(`✓ ${cmd}`);
            } catch (e) {
                log(`Error: ${e.message}`);
            }
        }
        
        function execTap() {
            const x = document.getElementById('tapX').value;
            const y = document.getElementById('tapY').value;
            if (x && y) exec('tap', `${x} ${y}`);
        }
        
        function execText() {
            const text = document.getElementById('textInput').value;
            if (text) exec('text', text);
        }
        
        function execUrl() {
            const url = document.getElementById('urlInput').value;
            if (url) exec('openurl', url);
        }
        
        function execCustom() {
            const cmd = document.getElementById('customCmd').value;
            if (cmd) {
                const parts = cmd.split(' ');
                exec(parts[0], parts.slice(1).join(' '));
            }
        }
        
        async function loadStatus() {
            try {
                const res = await fetch('/api/status');
                const data = await res.json();
                document.getElementById('status').textContent = data.status;
                document.getElementById('device').textContent = data.info.split('\n')[0];
                const level = data.battery.match(/level: (\d+)/);
                document.getElementById('battery').textContent = level ? level[1] + '%' : '--';
            } catch (e) {
                document.getElementById('status').textContent = 'Offline';
            }
        }
        
        loadStatus();
        setInterval(loadStatus, 5000);
    </script>
</body>
</html>
HTML_END

echo "✓ Web UI created"
echo ""

cat > ~/phonegate/start.sh << 'START_END'
#!/data/data/com.termux/files/usr/bin/bash
cd ~/phonegate
IP=$(ip route get 1 2>/dev/null | grep -oP 'src \K\S+' || echo "unknown")
echo ""
echo "🚀 Starting Phone Gateway..."
echo "📱 Access URL: http://${IP}:3000"
echo ""
node server.js
START_END

chmod +x ~/phonegate/start.sh

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "                             ✅ INSTALLATION COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 SETUP STEPS:"
echo ""
echo "1. Export Shizuku files:"
echo "   • Open Shizuku app"
echo "   • Tap 'Use Shizuku in terminal apps'"
echo "   • Tap 'Export files'"
echo "   • The rish_shizuku.dex will be copied to ~/rish_shizuku.dex"
echo ""
echo "2. Start the gateway:"
echo "   cd ~/phonegate"
echo "   ./start.sh"
echo ""
echo "3. Connect from other devices:"
echo "   • Enable hotspot on this phone"
echo "   • Connect other devices to the hotspot"
echo "   • Open browser and go to the URL shown"
echo "   • No password needed - direct access!"
echo ""
echo "4. Features:"
echo "   ✓ 25+ Phone control commands"
echo "   ✓ WiFi/Hotspot remote access"
echo "   ✓ Clean web interface"
echo "   ✓ Real-time status"
echo "   ✓ No authentication required"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
