#!/data/data/com.termux/files/usr/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
export LANG=C
export LC_ALL=C

clear
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "                    PHONE GATEWAY CONTROLLER v5.0"
echo "                 Fixed Network | Connection Logs | Fast Access"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

pkill -f "node.*gateway" 2>/dev/null || true
pkill -f "http-server" 2>/dev/null || true
pkill -f "python.*http.server" 2>/dev/null || true

echo "[1/7] Installing packages..."
pkg update -y 2>&1 | grep -E "(Reading|Building)" || true
pkg install -y nodejs python git curl jq termux-api net-tools nmap dnsutils 2>&1 | grep -E "(Setting up|Unpacking)" || true
pip install requests 2>/dev/null || true
echo ""

echo "[2/7] Creating project..."
rm -rf ~/phonegate 2>/dev/null || true
mkdir -p ~/phonegate/{web,data,scripts}
cd ~/phonegate
echo ""

echo "[3/7] Shizuku setup..."
termux-setup-storage 2>/dev/null || true
sleep 1

cat > ~/phonegate/shizuku_setup.sh << 'SHIZUKU'
#!/data/data/com.termux/files/usr/bin/bash
BIN=/data/data/com.termux/files/usr/bin
HOME=/data/data/com.termux/files/home
cat > "${BIN}/rish" << 'RISH'
#!/data/data/com.termux/files/usr/bin/bash
[ -z "$RISH_APPLICATION_ID" ] && export RISH_APPLICATION_ID="com.termux"
DEX="$HOME/rish_shizuku.dex"
if [ ! -f "$DEX" ]; then
    echo "ERROR: rish_shizuku.dex not found. Export from Shizuku app first."
    exit 1
fi
exec /system/bin/app_process -Djava.class.path="$DEX" /system/bin --nice-name=rish rikka.shizuku.shell.ShizukuShellLoader "$@"
RISH
chmod +x "${BIN}/rish"
SHIZUKU
chmod +x ~/phonegate/shizuku_setup.sh
bash ~/phonegate/shizuku_setup.sh 2>/dev/null || true
echo ""

echo "[4/7] Creating controller..."
cat > ~/phonegate/control.sh << 'CONTROL'
#!/data/data/com.termux/files/usr/bin/bash
exec_cmd() {
    if command -v rish &>/dev/null; then
        rish -c "$1" 2>&1
    else
        echo "ERROR: Shizuku not configured"
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
CONTROL
chmod +x ~/phonegate/control.sh
echo ""

echo "[5/7] Creating gateway server with fixed network..."
cat > ~/phonegate/server.js << 'SERVER'
const http = require('http');
const fs = require('fs');
const path = require('path');
const { exec, execSync } = require('child_process');
const os = require('os');

const PORT = process.env.PORT || 3000;
const controlScript = path.join(__dirname, 'control.sh');
const connections = new Map();
let requestCount = 0;
let startTime = Date.now();

const mimeTypes = {
    '.html': 'text/html',
    '.css': 'text/css',
    '.js': 'text/javascript',
    '.json': 'application/json',
    '.svg': 'image/svg+xml',
    '.png': 'image/png',
    '.ico': 'image/x-icon'
};

function getAllNetworkIPs() {
    const interfaces = os.networkInterfaces();
    const ips = [];
    
    for (const name of Object.keys(interfaces)) {
        for (const iface of interfaces[name]) {
            if (iface.family === 'IPv4' && !iface.internal) {
                ips.push({ name, ip: iface.address });
            }
        }
    }
    return ips;
}

function getBestIP() {
    const ips = getAllNetworkIPs();
    
    for (const {name, ip} of ips) {
        if (name.includes('wlan') || name.includes('ap') || name.includes('hotspot')) {
            return ip;
        }
    }
    
    for (const {name, ip} of ips) {
        if (ip.startsWith('192.168.')) {
            return ip;
        }
    }
    
    try {
        const route = execSync("ip route get 1 2>/dev/null | grep -oP 'src \\K\\S+'", {shell: '/bin/bash'}).toString().trim();
        if (route) return route;
    } catch(e) {}
    
    return ips.length > 0 ? ips[0].ip : '0.0.0.0';
}

function formatBytes(bytes) {
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}

function logConnection(ip, msg, details = '') {
    const time = new Date().toLocaleTimeString('en-US', { hour12: false });
    const conn = connections.get(ip);
    const reqCount = conn ? conn.requests : 0;
    
    const symbols = {
        'CONNECT': '🟢',
        'COMMAND': '⚡',
        'STATUS': '📊',
        'DISCONNECT': '🔴',
        'ERROR': '❌'
    };
    
    const symbol = symbols[msg] || '📡';
    console.log(`[${time}] ${symbol} ${ip} | ${msg}${details ? ' | ' + details : ''} | reqs: ${reqCount}`);
    
    if (msg === 'CONNECT') {
        console.log(`         └─ User-Agent: ${details.substring(0, 50)}`);
    }
}

function execCommand(cmd, args = '') {
    return new Promise((resolve) => {
        const fullCmd = `bash ${controlScript} ${cmd} ${args} 2>&1`;
        exec(fullCmd, { timeout: 15000, maxBuffer: 1024 * 1024 }, (err, stdout, stderr) => {
            if (err) {
                resolve(`Error: ${err.message}`);
            } else {
                resolve(stdout || stderr || 'Command executed successfully');
            }
        });
    });
}

const server = http.createServer(async (req, res) => {
    const clientIP = (req.headers['x-forwarded-for'] || 
                      req.connection.remoteAddress || 
                      req.socket.remoteAddress || 
                      'unknown').replace('::ffff:', '').replace('::1', '127.0.0.1');
    
    requestCount++;
    
    const isNew = !connections.has(clientIP);
    if (isNew) {
        connections.set(clientIP, { 
            firstSeen: new Date(), 
            requests: 0,
            userAgent: req.headers['user-agent'] || 'Unknown',
            lastSeen: new Date()
        });
        logConnection(clientIP, 'CONNECT', req.headers['user-agent'] || '');
    }
    
    const connData = connections.get(clientIP);
    connData.requests++;
    connData.lastSeen = new Date();
    
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    
    if (req.method === 'OPTIONS') {
        res.writeHead(204);
        res.end();
        return;
    }
    
    const url = new URL(req.url, `http://${req.headers.host}`);
    
    if (url.pathname === '/api/status') {
        logConnection(clientIP, 'STATUS');
        const battery = await execCommand('battery');
        const info = await execCommand('info');
        const networkIPs = getAllNetworkIPs();
        
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ 
            battery, 
            info, 
            status: 'online',
            uptime: Math.floor((Date.now() - startTime) / 1000),
            connections: connections.size,
            totalRequests: requestCount,
            network: networkIPs,
            serverIP: getBestIP()
        }));
        return;
    }
    
    if (url.pathname === '/api/connections') {
        const connList = [];
        connections.forEach((data, ip) => {
            connList.push({
                ip,
                requests: data.requests,
                firstSeen: data.firstSeen,
                lastSeen: data.lastSeen,
                userAgent: data.userAgent
            });
        });
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ connections: connList, total: connections.size }));
        return;
    }
    
    if (url.pathname === '/api/command') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', async () => {
            try {
                const { cmd, args } = JSON.parse(body);
                logConnection(clientIP, 'COMMAND', `${cmd} ${args || ''}`);
                const result = await execCommand(cmd, args);
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ result, timestamp: Date.now() }));
            } catch (e) {
                logConnection(clientIP, 'ERROR', e.message);
                res.writeHead(400);
                res.end(JSON.stringify({ error: 'Invalid request' }));
            }
        });
        return;
    }
    
    if (url.pathname === '/api/config') {
        const configPath = path.join(require('os').homedir(), '.phonegate/config.json');
        if (req.method === 'GET') {
            if (fs.existsSync(configPath)) {
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(fs.readFileSync(configPath));
            } else {
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ 
                    gemini_api_key: '', 
                    telegram_bot_token: '', 
                    telegram_chat_id: '', 
                    telegram_enabled: false 
                }));
            }
        } else if (req.method === 'POST') {
            let body = '';
            req.on('data', chunk => body += chunk);
            req.on('end', () => {
                const configDir = path.join(require('os').homedir(), '.phonegate');
                if (!fs.existsSync(configDir)) fs.mkdirSync(configDir, { recursive: true });
                fs.writeFileSync(configPath, body);
                logConnection(clientIP, 'CONFIG', 'Settings updated');
                res.writeHead(200);
                res.end(JSON.stringify({ saved: true }));
            });
        }
        return;
    }
    
    if (url.pathname === '/api/commands') {
        const commands = [
            'tap [x] [y]', 'swipe [x1] [y1] [x2] [y2] [dur]', 'text [content]', 
            'key [code]', 'home', 'back', 'recent', 'power', 'volup', 'voldown',
            'screenshot', 'openapp [package]', 'openurl [url]', 'battery',
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
            res.writeHead(200, { 
                'Content-Type': mimeTypes[ext] || 'text/plain',
                'Cache-Control': 'no-cache'
            });
            res.end(content);
        }
    });
});

server.on('error', (err) => {
    console.error('Server error:', err);
    if (err.code === 'EADDRINUSE') {
        console.log(`Port ${PORT} is in use. Trying ${PORT + 1}...`);
        server.listen(PORT + 1, '0.0.0.0');
    }
});

server.listen(PORT, '0.0.0.0', () => {
    const ip = getBestIP();
    const allIPs = getAllNetworkIPs();
    
    console.log('');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('                    🔥 PHONE GATEWAY ONLINE 🔥');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('');
    console.log('📡 ACCESS URLs (use these from other devices):');
    console.log('');
    
    allIPs.forEach(({name, ip}) => {
        console.log(`   ▶ http://${ip}:${PORT}  (${name})`);
    });
    
    console.log('');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('📊 Server Status:');
    console.log(`   • Port: ${PORT}`);
    console.log(`   • Interface: 0.0.0.0 (all interfaces)`);
    console.log(`   • Started: ${new Date().toLocaleString()}`);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('');
    console.log('📱 Connection Instructions:');
    console.log('   1. Enable Hotspot on this device');
    console.log('   2. Connect other devices to this hotspot');
    console.log('   3. Open any URL above in browser');
    console.log('');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('📊 Waiting for connections... (logs will appear below)');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('');
});

setInterval(() => {
    const now = Date.now();
    const toRemove = [];
    
    connections.forEach((data, ip) => {
        if (now - data.lastSeen > 300000) {
            toRemove.push(ip);
        }
    });
    
    toRemove.forEach(ip => {
        logConnection(ip, 'DISCONNECT', 'timeout');
        connections.delete(ip);
    });
    
    if (connections.size > 0) {
        console.log('');
        console.log(`[${new Date().toLocaleTimeString()}] 📊 ACTIVE SESSIONS: ${connections.size} | Total Requests: ${requestCount}`);
        connections.forEach((data, ip) => {
            console.log(`   └─ ${ip} | ${data.requests} requests | Last: ${data.lastSeen.toLocaleTimeString()}`);
        });
        console.log('');
    }
}, 30000);

process.on('SIGINT', () => {
    console.log('\nShutting down gateway...');
    process.exit(0);
});
SERVER
echo ""

echo "[6/7] Creating web interface..."
cat > ~/phonegate/web/index.html << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=yes">
    <title>Phone Gateway v5</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 16px;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        
        .header {
            background: rgba(255,255,255,0.95);
            padding: 20px 24px;
            border-radius: 16px;
            margin-bottom: 20px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
        }
        .header h1 {
            font-size: 1.8rem;
            background: linear-gradient(135deg, #667eea, #764ba2);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .header p { color: #666; margin-top: 4px; }
        
        .status-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
            gap: 12px;
            margin-bottom: 20px;
        }
        .stat-card {
            background: rgba(255,255,255,0.95);
            padding: 16px;
            border-radius: 12px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.1);
        }
        .stat-label { font-size: 12px; color: #888; text-transform: uppercase; letter-spacing: 0.5px; }
        .stat-value { font-size: 1.6rem; font-weight: bold; color: #333; }
        .online { color: #10b981 !important; }
        .offline { color: #ef4444 !important; }
        
        .panel {
            background: rgba(255,255,255,0.95);
            padding: 20px;
            border-radius: 16px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
            margin-bottom: 20px;
        }
        .panel h2 {
            font-size: 1.2rem;
            color: #333;
            margin-bottom: 16px;
            padding-bottom: 8px;
            border-bottom: 2px solid #667eea;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        
        .btn-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(90px, 1fr));
            gap: 10px;
        }
        .btn {
            background: linear-gradient(135deg, #667eea, #764ba2);
            color: white;
            border: none;
            padding: 14px 8px;
            border-radius: 10px;
            font-size: 13px;
            font-weight: 500;
            cursor: pointer;
            transition: transform 0.2s, box-shadow 0.2s;
            box-shadow: 0 4px 10px rgba(102, 126, 234, 0.3);
        }
        .btn:hover { transform: translateY(-2px); box-shadow: 0 6px 15px rgba(102, 126, 234, 0.4); }
        .btn:active { transform: translateY(0); }
        
        .input-group {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            margin-bottom: 12px;
        }
        .input-group input {
            flex: 1;
            min-width: 120px;
            padding: 12px 16px;
            border: 2px solid #e5e7eb;
            border-radius: 10px;
            font-size: 14px;
            transition: border-color 0.2s;
        }
        .input-group input:focus { outline: none; border-color: #667eea; }
        .input-group button {
            padding: 12px 24px;
            background: #667eea;
            color: white;
            border: none;
            border-radius: 10px;
            font-weight: 500;
            cursor: pointer;
        }
        
        .output {
            background: #1e1e2e;
            color: #a6e3a1;
            padding: 16px;
            border-radius: 10px;
            font-family: 'Monaco', 'Menlo', monospace;
            font-size: 13px;
            min-height: 200px;
            max-height: 400px;
            overflow-y: auto;
            white-space: pre-wrap;
            line-height: 1.5;
        }
        
        .toast {
            position: fixed;
            bottom: 20px;
            right: 20px;
            background: #333;
            color: white;
            padding: 12px 24px;
            border-radius: 50px;
            font-weight: 500;
            animation: slideIn 0.3s;
            z-index: 1000;
        }
        @keyframes slideIn { from { opacity: 0; transform: translateX(20px); } to { opacity: 1; transform: translateX(0); } }
        
        @media (max-width: 600px) {
            body { padding: 10px; }
            .btn-grid { grid-template-columns: repeat(3, 1fr); }
            .header h1 { font-size: 1.4rem; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Phone Gateway Controller v5</h1>
            <p id="connectionInfo">Ready for connections...</p>
        </div>
        
        <div class="status-grid">
            <div class="stat-card"><div class="stat-label">Status</div><div class="stat-value online" id="status">Online</div></div>
            <div class="stat-card"><div class="stat-label">Device</div><div class="stat-value" id="device" style="font-size:1rem;">Loading...</div></div>
            <div class="stat-card"><div class="stat-label">Battery</div><div class="stat-value" id="battery">--%</div></div>
            <div class="stat-card"><div class="stat-label">Clients</div><div class="stat-value" id="clients">0</div></div>
        </div>
        
        <div class="panel">
            <h2>Quick Controls</h2>
            <div class="btn-grid">
                <button class="btn" onclick="exec('home')">Home</button>
                <button class="btn" onclick="exec('back')">Back</button>
                <button class="btn" onclick="exec('recent')">Recent</button>
                <button class="btn" onclick="exec('power')">Power</button>
                <button class="btn" onclick="exec('volup')">Vol+</button>
                <button class="btn" onclick="exec('voldown')">Vol-</button>
                <button class="btn" onclick="exec('wifi_on')">WiFi ON</button>
                <button class="btn" onclick="exec('wifi_off')">WiFi OFF</button>
                <button class="btn" onclick="exec('flashlight_on')">Flash ON</button>
                <button class="btn" onclick="exec('flashlight_off')">Flash OFF</button>
                <button class="btn" onclick="exec('screenshot')">Screenshot</button>
                <button class="btn" onclick="exec('battery')">Battery</button>
            </div>
        </div>
        
        <div class="panel">
            <h2>Custom Commands</h2>
            <div class="input-group">
                <input type="text" id="tapX" placeholder="X">
                <input type="text" id="tapY" placeholder="Y">
                <button onclick="execTap()">Tap</button>
            </div>
            <div class="input-group">
                <input type="text" id="textInput" placeholder="Text to type...">
                <button onclick="execText()">Type</button>
            </div>
            <div class="input-group">
                <input type="text" id="urlInput" placeholder="URL or app package">
                <button onclick="execUrl()">Open</button>
            </div>
            <div class="input-group">
                <input type="text" id="shellInput" placeholder="Shell command">
                <button onclick="execShell()">Execute</button>
            </div>
        </div>
        
        <div class="panel">
            <h2>Console Output</h2>
            <div class="output" id="output">Gateway ready. Waiting for commands...</div>
        </div>
    </div>
    
    <script>
        const output = document.getElementById('output');
        const statusEl = document.getElementById('status');
        
        function log(msg) {
            const time = new Date().toLocaleTimeString();
            output.textContent = `[${time}] ${msg}\n` + output.textContent;
        }
        
        function toast(msg) {
            const t = document.createElement('div');
            t.className = 'toast';
            t.textContent = msg;
            document.body.appendChild(t);
            setTimeout(() => t.remove(), 3000);
        }
        
        async function exec(cmd, args = '') {
            try {
                const res = await fetch('/api/command', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({cmd, args})
                });
                const data = await res.json();
                log(`> ${cmd} ${args}\n  ${data.result}`);
                toast(`${cmd} executed`);
            } catch(e) {
                log(`Error: ${e.message}`);
                statusEl.textContent = 'Offline';
                statusEl.className = 'stat-value offline';
            }
        }
        
        function execTap() {
            const x = document.getElementById('tapX').value;
            const y = document.getElementById('tapY').value;
            if(x && y) exec('tap', `${x} ${y}`);
        }
        
        function execText() {
            const t = document.getElementById('textInput').value;
            if(t) exec('text', t);
        }
        
        function execUrl() {
            const u = document.getElementById('urlInput').value;
            if(u) exec(u.includes('://') ? 'openurl' : 'openapp', u);
        }
        
        function execShell() {
            const s = document.getElementById('shellInput').value;
            if(s) exec('shell', `"${s}"`);
        }
        
        async function loadStatus() {
            try {
                const res = await fetch('/api/status');
                const data = await res.json();
                
                statusEl.textContent = 'Online';
                statusEl.className = 'stat-value online';
                
                const info = data.info.split('\n');
                document.getElementById('device').textContent = info[0] || 'Android';
                
                const level = data.battery.match(/level:\s*(\d+)/);
                document.getElementById('battery').textContent = level ? level[1] + '%' : '--%';
                
                document.getElementById('clients').textContent = data.connections || 0;
                document.getElementById('connectionInfo').textContent = 
                    `Server: ${data.serverIP}:3000 | Uptime: ${Math.floor(data.uptime/60)}m | Clients: ${data.connections}`;
            } catch(e) {
                statusEl.textContent = 'Offline';
                statusEl.className = 'stat-value offline';
                document.getElementById('connectionInfo').textContent = 'Connection lost. Retrying...';
            }
        }
        
        loadStatus();
        setInterval(loadStatus, 3000);
    </script>
</body>
</html>
HTML
echo ""

echo "[7/7] Creating start script..."
cat > ~/phonegate/start.sh << 'START'
#!/data/data/com.termux/files/usr/bin/bash
cd ~/phonegate
echo "Starting Phone Gateway v5..."
echo ""
mkdir -p ~/.phonegate
exec node server.js
START
chmod +x ~/phonegate/start.sh

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "                         ✅ INSTALLATION COMPLETE v5"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "QUICK START:"
echo ""
echo "1. Export Shizuku files:"
echo "   Open Shizuku → Use Shizuku in terminal apps → Export files"
echo ""
echo "2. Start gateway:"
echo "   cd ~/phonegate && ./start.sh"
echo ""
echo "3. Connect other devices:"
echo "   Enable hotspot on this phone"
echo "   Connect other devices to hotspot"
echo "   Open displayed URL in browser"
echo ""
echo "📊 CONNECTION LOGS:"
echo "   • Shows when devices connect/disconnect"
echo "   • Shows every command executed"
echo "   • Shows active clients every 30 seconds"
echo "   • Multiple URLs displayed for different network interfaces"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
