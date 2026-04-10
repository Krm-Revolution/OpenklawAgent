#!/data/data/com.termux/files/usr/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
export LANG=C
export LC_ALL=C

clear
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "                    PHONE GATEWAY CONTROLLER v6.0"
echo "            50+ Commands | Screen Cast | Full Remote Control"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

pkill -f "node.*gateway" 2>/dev/null || true
pkill -f "http-server" 2>/dev/null || true
pkill -f "python.*http.server" 2>/dev/null || true

echo "[1/8] Installing packages..."
pkg update -y 2>&1 | grep -E "(Reading|Building)" || true
pkg install -y nodejs python git curl jq termux-api net-tools nmap dnsutils imagemagick 2>&1 | grep -E "(Setting up|Unpacking)" || true
pip install requests 2>/dev/null || true
npm install -g websocket 2>/dev/null || true
echo ""

echo "[2/8] Creating project..."
rm -rf ~/phonegate 2>/dev/null || true
mkdir -p ~/phonegate/{web,data,scripts,tmp}
cd ~/phonegate
echo ""

echo "[3/8] Shizuku setup..."
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

echo "[4/8] Creating enhanced controller (50+ commands)..."
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
    mute) exec_cmd "input keyevent 164" ;;
    play) exec_cmd "input keyevent 126" ;;
    pause) exec_cmd "input keyevent 127" ;;
    next) exec_cmd "input keyevent 87" ;;
    prev) exec_cmd "input keyevent 88" ;;
    screenshot) 
        FILE="/sdcard/screenshot_$(date +%s).png"
        exec_cmd "screencap -p $FILE" && echo "$FILE"
        ;;
    screenstream) exec_cmd "screencap -p /sdcard/screenstream.png" && echo "/sdcard/screenstream.png" ;;
    openapp) exec_cmd "monkey -p $2 1" ;;
    closeapp) exec_cmd "am force-stop $2" ;;
    openurl) exec_cmd "am start -a android.intent.action.VIEW -d '$2'" ;;
    battery) exec_cmd "dumpsys battery" | grep -E "level|status|temperature|voltage" ;;
    brightness) exec_cmd "settings put system screen_brightness $2" ;;
    brightness_auto) exec_cmd "settings put system screen_brightness_mode $2" ;;
    volume) exec_cmd "media volume --set $2" ;;
    wifi_on) exec_cmd "svc wifi enable" ;;
    wifi_off) exec_cmd "svc wifi disable" ;;
    bluetooth_on) exec_cmd "cmd bluetooth_manager enable" ;;
    bluetooth_off) exec_cmd "cmd bluetooth_manager disable" ;;
    location_on) exec_cmd "settings put secure location_mode 3" ;;
    location_off) exec_cmd "settings put secure location_mode 0" ;;
    flashlight_on) exec_cmd "cmd flashlight enable" ;;
    flashlight_off) exec_cmd "cmd flashlight disable" ;;
    airplane_on) exec_cmd "settings put global airplane_mode_on 1; am broadcast -a android.intent.action.AIRPLANE_MODE" ;;
    airplane_off) exec_cmd "settings put global airplane_mode_on 0; am broadcast -a android.intent.action.AIRPLANE_MODE" ;;
    nfc_on) exec_cmd "svc nfc enable" ;;
    nfc_off) exec_cmd "svc nfc disable" ;;
    hotspot_on) exec_cmd "svc wifi enable; cmd wifi set-wifi-enabled enabled; service call connectivity 37 i32 1" ;;
    hotspot_off) exec_cmd "service call connectivity 37 i32 0" ;;
    reboot) exec_cmd "reboot" ;;
    reboot_recovery) exec_cmd "reboot recovery" ;;
    reboot_bootloader) exec_cmd "reboot bootloader" ;;
    lockscreen) exec_cmd "input keyevent 26; input keyevent 26" ;;
    sleep) exec_cmd "input keyevent 26" ;;
    wake) exec_cmd "input keyevent 224" ;;
    notify) exec_cmd "cmd notification post -S bigtext -t '$2' 'Gateway' '$3'" ;;
    toast) exec_cmd "cmd notification post -S toast -t '$2' 'Gateway' '$3'" ;;
    vibrate) exec_cmd "cmd vibrator vibrate ${2:-500}" ;;
    clipboard_get) exec_cmd "cmd clipboard get-text" ;;
    clipboard_set) exec_cmd "cmd clipboard set-text '$2'" ;;
    applist) exec_cmd "pm list packages -3" | sed 's/package://g' ;;
    sysapps) exec_cmd "pm list packages -s" | sed 's/package://g' ;;
    info) exec_cmd "getprop ro.product.model && getprop ro.build.version.release && getprop ro.product.manufacturer" ;;
    cpu) exec_cmd "cat /proc/cpuinfo | grep -E 'Processor|Hardware'" ;;
    memory) exec_cmd "dumpsys meminfo | grep -E 'Total RAM|Free RAM'" ;;
    storage) exec_cmd "df -h /data" ;;
    ui) exec_cmd "uiautomator dump /sdcard/ui.xml && cat /sdcard/ui.xml" ;;
    shell) exec_cmd "$2" ;;
    dial) exec_cmd "am start -a android.intent.action.CALL -d tel:$2" ;;
    sms) exec_cmd "am start -a android.intent.action.SENDTO -d sms:$2 --es sms_body '$3'" ;;
    search) exec_cmd "am start -a android.intent.action.WEB_SEARCH -e query '$2'" ;;
    camera) exec_cmd "am start -a android.media.action.IMAGE_CAPTURE" ;;
    record) exec_cmd "am start -a android.media.action.VIDEO_CAPTURE" ;;
    settings) exec_cmd "am start -a android.settings.SETTINGS" ;;
    wifi_settings) exec_cmd "am start -a android.settings.WIFI_SETTINGS" ;;
    bluetooth_settings) exec_cmd "am start -a android.settings.BLUETOOTH_SETTINGS" ;;
    app_settings) exec_cmd "am start -a android.settings.APPLICATION_SETTINGS" ;;
    display_settings) exec_cmd "am start -a android.settings.DISPLAY_SETTINGS" ;;
    sound_settings) exec_cmd "am start -a android.settings.SOUND_SETTINGS" ;;
    *) echo "Unknown: $1" ;;
esac
CONTROL
chmod +x ~/phonegate/control.sh
echo ""

echo "[5/8] Creating gateway server with screen cast..."
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
    '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript',
    '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png',
    '.jpg': 'image/jpeg', '.ico': 'image/x-icon'
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
        if (name.includes('wlan') || name.includes('ap') || name.includes('hotspot')) return ip;
    }
    for (const {name, ip} of ips) {
        if (ip.startsWith('192.168.')) return ip;
    }
    try {
        const route = execSync("ip route get 1 2>/dev/null | grep -oP 'src \\K\\S+'", {shell: '/bin/bash'}).toString().trim();
        if (route) return route;
    } catch(e) {}
    return ips.length > 0 ? ips[0].ip : '0.0.0.0';
}

function logConnection(ip, msg, details = '') {
    const time = new Date().toLocaleTimeString('en-US', { hour12: false });
    const conn = connections.get(ip);
    const reqCount = conn ? conn.requests : 0;
    const symbols = { 'CONNECT': '🟢', 'COMMAND': '⚡', 'STATUS': '📊', 'DISCONNECT': '🔴', 'ERROR': '❌', 'SCREEN': '📸' };
    const symbol = symbols[msg] || '📡';
    console.log(`[${time}] ${symbol} ${ip} | ${msg}${details ? ' | ' + details : ''} | reqs: ${reqCount}`);
}

function execCommand(cmd, args = '') {
    return new Promise((resolve) => {
        const fullCmd = `bash ${controlScript} ${cmd} ${args} 2>&1`;
        exec(fullCmd, { timeout: 15000, maxBuffer: 1024 * 1024 }, (err, stdout, stderr) => {
            if (err) resolve(`Error: ${err.message}`);
            else resolve(stdout || stderr || 'Command executed successfully');
        });
    });
}

const server = http.createServer(async (req, res) => {
    const clientIP = (req.headers['x-forwarded-for'] || req.connection.remoteAddress || 
                      req.socket.remoteAddress || 'unknown').replace('::ffff:', '').replace('::1', '127.0.0.1');
    requestCount++;
    
    if (!connections.has(clientIP)) {
        connections.set(clientIP, { firstSeen: new Date(), requests: 0, userAgent: req.headers['user-agent'] || 'Unknown', lastSeen: new Date() });
        logConnection(clientIP, 'CONNECT', req.headers['user-agent'] || '');
    }
    const connData = connections.get(clientIP);
    connData.requests++;
    connData.lastSeen = new Date();
    
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }
    
    const url = new URL(req.url, `http://${req.headers.host}`);
    
    if (url.pathname === '/api/status') {
        const battery = await execCommand('battery');
        const info = await execCommand('info');
        const memory = await execCommand('memory');
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ battery, info, memory, status: 'online', uptime: Math.floor((Date.now() - startTime) / 1000),
            connections: connections.size, totalRequests: requestCount, serverIP: getBestIP(), network: getAllNetworkIPs() }));
        return;
    }
    
    if (url.pathname === '/api/screen') {
        logConnection(clientIP, 'SCREEN');
        await execCommand('screenstream');
        const screenPath = '/sdcard/screenstream.png';
        try {
            const img = fs.readFileSync(screenPath);
            res.writeHead(200, { 'Content-Type': 'image/png', 'Cache-Control': 'no-cache' });
            res.end(img);
        } catch(e) {
            res.writeHead(500);
            res.end('Screenshot failed');
        }
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
                res.writeHead(400); res.end(JSON.stringify({ error: 'Invalid request' }));
            }
        });
        return;
    }
    
    if (url.pathname === '/api/commands') {
        const cmds = ['tap','swipe','text','key','home','back','recent','power','volup','voldown','mute','play','pause','next','prev',
            'screenshot','openapp','closeapp','openurl','battery','brightness','brightness_auto','volume','wifi_on','wifi_off',
            'bluetooth_on','bluetooth_off','location_on','location_off','flashlight_on','flashlight_off','airplane_on','airplane_off',
            'nfc_on','nfc_off','hotspot_on','hotspot_off','reboot','reboot_recovery','reboot_bootloader','lockscreen','sleep','wake',
            'notify','toast','vibrate','clipboard_get','clipboard_set','applist','sysapps','info','cpu','memory','storage','ui','shell',
            'dial','sms','search','camera','record','settings','wifi_settings','bluetooth_settings','app_settings','display_settings','sound_settings'];
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ commands: cmds }));
        return;
    }
    
    let filePath = path.join(__dirname, 'web', url.pathname === '/' ? 'index.html' : url.pathname);
    fs.readFile(filePath, (err, content) => {
        if (err) { res.writeHead(404); res.end('Not Found'); }
        else {
            const ext = path.extname(filePath);
            res.writeHead(200, { 'Content-Type': mimeTypes[ext] || 'text/plain', 'Cache-Control': 'no-cache' });
            res.end(content);
        }
    });
});

server.listen(PORT, '0.0.0.0', () => {
    const allIPs = getAllNetworkIPs();
    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('                    🔥 PHONE GATEWAY ONLINE v6 🔥');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('\n📡 ACCESS URLs:');
    allIPs.forEach(({name, ip}) => console.log(`   ▶ http://${ip}:${PORT}  (${name})`));
    console.log('\n📱 Connect other devices to hotspot and open URL above.\n');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
});

setInterval(() => {
    const now = Date.now();
    connections.forEach((data, ip) => { if (now - data.lastSeen > 300000) { connections.delete(ip); } });
    if (connections.size > 0) {
        console.log(`[${new Date().toLocaleTimeString()}] 📊 Active: ${connections.size} | Requests: ${requestCount}`);
        connections.forEach((d, ip) => console.log(`   └─ ${ip} | ${d.requests} reqs`));
    }
}, 30000);
SERVER
echo ""

echo "[6/8] Creating full-featured web UI with screen cast..."
cat > ~/phonegate/web/index.html << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=yes">
    <title>Phone Gateway v6</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%); min-height: 100vh; padding: 12px; color: #fff; }
        .container { max-width: 1400px; margin: 0 auto; }
        nav { display: flex; gap: 8px; margin-bottom: 16px; flex-wrap: wrap; }
        .nav-btn { background: rgba(255,255,255,0.1); border: 1px solid rgba(255,255,255,0.2); color: white; padding: 12px 18px; border-radius: 40px; cursor: pointer; font-size: 14px; font-weight: 500; display: flex; align-items: center; gap: 8px; backdrop-filter: blur(10px); }
        .nav-btn.active { background: #e94560; border-color: #e94560; }
        .page { display: none; }
        .page.active { display: block; }
        .status-bar { display: grid; grid-template-columns: repeat(auto-fit, minmax(130px, 1fr)); gap: 10px; margin-bottom: 16px; }
        .stat { background: rgba(255,255,255,0.08); padding: 14px; border-radius: 16px; backdrop-filter: blur(10px); border: 1px solid rgba(255,255,255,0.1); }
        .stat-label { font-size: 11px; text-transform: uppercase; color: #888; }
        .stat-value { font-size: 1.5rem; font-weight: bold; }
        .panel { background: rgba(255,255,255,0.05); backdrop-filter: blur(15px); padding: 20px; border-radius: 24px; border: 1px solid rgba(255,255,255,0.1); margin-bottom: 20px; }
        .panel h2 { font-size: 1.2rem; margin-bottom: 16px; display: flex; align-items: center; gap: 10px; color: #e94560; }
        .btn-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(100px, 1fr)); gap: 10px; }
        .btn { background: rgba(255,255,255,0.1); border: 1px solid rgba(255,255,255,0.15); color: white; padding: 14px 8px; border-radius: 14px; font-size: 13px; font-weight: 500; cursor: pointer; transition: all 0.2s; }
        .btn:hover { background: #e94560; }
        .input-row { display: flex; gap: 10px; margin-bottom: 12px; flex-wrap: wrap; }
        .input-row input { flex: 1; min-width: 140px; padding: 14px; background: rgba(0,0,0,0.3); border: 1px solid rgba(255,255,255,0.2); border-radius: 14px; color: white; }
        .input-row button { padding: 14px 28px; background: #e94560; border: none; border-radius: 14px; color: white; font-weight: bold; cursor: pointer; }
        .screen-container { text-align: center; }
        #screenImg { max-width: 100%; border-radius: 20px; box-shadow: 0 10px 30px rgba(0,0,0,0.5); border: 2px solid rgba(255,255,255,0.2); }
        .output { background: #0a0a14; color: #0f0; padding: 16px; border-radius: 16px; font-family: monospace; font-size: 13px; min-height: 180px; max-height: 350px; overflow-y: auto; white-space: pre-wrap; }
        .toast { position: fixed; bottom: 20px; right: 20px; background: #e94560; padding: 12px 24px; border-radius: 50px; animation: slide 0.3s; z-index: 1000; }
        @keyframes slide { from { opacity: 0; transform: translateX(20px); } to { opacity: 1; transform: translateX(0); } }
        @media (max-width: 600px) { .btn-grid { grid-template-columns: repeat(3, 1fr); } }
    </style>
</head>
<body>
<div class="container">
    <nav>
        <button class="nav-btn active" data-page="control">🎮 Control</button>
        <button class="nav-btn" data-page="screen">📺 Screen Cast</button>
        <button class="nav-btn" data-page="advanced">⚙️ Advanced</button>
        <button class="nav-btn" data-page="settings">🔧 Settings</button>
    </nav>
    
    <div class="status-bar">
        <div class="stat"><div class="stat-label">Status</div><div class="stat-value" id="status">● Online</div></div>
        <div class="stat"><div class="stat-label">Device</div><div class="stat-value" id="device" style="font-size:1rem;">-</div></div>
        <div class="stat"><div class="stat-label">Battery</div><div class="stat-value" id="battery">-</div></div>
        <div class="stat"><div class="stat-label">Clients</div><div class="stat-value" id="clients">0</div></div>
    </div>
    
    <div id="controlPage" class="page active">
        <div class="panel">
            <h2>Navigation</h2>
            <div class="btn-grid">
                <button class="btn" onclick="exec('home')">🏠 Home</button>
                <button class="btn" onclick="exec('back')">⬅️ Back</button>
                <button class="btn" onclick="exec('recent')">📱 Recent</button>
                <button class="btn" onclick="exec('power')">⏻ Power</button>
                <button class="btn" onclick="exec('volup')">🔊 Vol+</button>
                <button class="btn" onclick="exec('voldown')">🔉 Vol-</button>
                <button class="btn" onclick="exec('mute')">🔇 Mute</button>
                <button class="btn" onclick="exec('lockscreen')">🔒 Lock</button>
            </div>
        </div>
        <div class="panel">
            <h2>Media</h2>
            <div class="btn-grid">
                <button class="btn" onclick="exec('play')">▶ Play</button>
                <button class="btn" onclick="exec('pause')">⏸ Pause</button>
                <button class="btn" onclick="exec('next')">⏭ Next</button>
                <button class="btn" onclick="exec('prev')">⏮ Prev</button>
            </div>
        </div>
        <div class="panel">
            <h2>Connectivity</h2>
            <div class="btn-grid">
                <button class="btn" onclick="exec('wifi_on')">📶 WiFi ON</button>
                <button class="btn" onclick="exec('wifi_off')">📴 WiFi OFF</button>
                <button class="btn" onclick="exec('bluetooth_on')">🔵 BT ON</button>
                <button class="btn" onclick="exec('bluetooth_off')">🔘 BT OFF</button>
                <button class="btn" onclick="exec('location_on')">📍 GPS ON</button>
                <button class="btn" onclick="exec('location_off')">🌍 GPS OFF</button>
                <button class="btn" onclick="exec('flashlight_on')">💡 Flash</button>
                <button class="btn" onclick="exec('airplane_on')">✈️ Airplane</button>
            </div>
        </div>
    </div>
    
    <div id="screenPage" class="page">
        <div class="panel">
            <h2>Live Screen</h2>
            <div class="screen-container">
                <img id="screenImg" src="/api/screen" alt="Phone Screen" onerror="this.src='data:image/svg+xml,%3Csvg xmlns=\'http://www.w3.org/2000/svg\' width=\'300\' height=\'600\'%3E%3Crect width=\'300\' height=\'600\' fill=\'%23111\'/%3E%3Ctext x=\'50\' y=\'300\' fill=\'%23fff\'%3EScreen refresh%3C/text%3E%3C/svg%3E'">
            </div>
            <div style="margin-top:16px; display:flex; gap:10px; justify-content:center;">
                <button class="btn" onclick="refreshScreen()">🔄 Refresh</button>
                <button class="btn" onclick="startAutoRefresh()">▶ Auto</button>
                <button class="btn" onclick="stopAutoRefresh()">⏹ Stop</button>
                <button class="btn" onclick="exec('screenshot')">📸 Save</button>
            </div>
        </div>
        <div class="panel">
            <h2>Tap on Screen</h2>
            <div class="input-row">
                <input type="number" id="tapX" placeholder="X" value="540">
                <input type="number" id="tapY" placeholder="Y" value="1120">
                <button onclick="execTap()">👆 Tap</button>
            </div>
            <div class="input-row">
                <input type="text" id="textInput" placeholder="Type text...">
                <button onclick="execText()">⌨️ Type</button>
            </div>
        </div>
    </div>
    
    <div id="advancedPage" class="page">
        <div class="panel">
            <h2>App Control</h2>
            <div class="input-row">
                <input type="text" id="appPackage" placeholder="Package name (e.g. com.whatsapp)">
                <button onclick="exec('openapp', document.getElementById('appPackage').value)">Open</button>
                <button onclick="exec('closeapp', document.getElementById('appPackage').value)">Force Stop</button>
            </div>
            <div class="input-row">
                <input type="text" id="urlInput" placeholder="URL">
                <button onclick="exec('openurl', document.getElementById('urlInput').value)">🌐 Open</button>
            </div>
        </div>
        <div class="panel">
            <h2>System</h2>
            <div class="btn-grid">
                <button class="btn" onclick="exec('reboot')">🔄 Reboot</button>
                <button class="btn" onclick="exec('reboot_recovery')">⚙️ Recovery</button>
                <button class="btn" onclick="exec('settings')">⚙️ Settings</button>
                <button class="btn" onclick="exec('wifi_settings')">📶 WiFi Settings</button>
                <button class="btn" onclick="exec('display_settings')">🖥️ Display</button>
                <button class="btn" onclick="exec('sound_settings')">🔊 Sound</button>
                <button class="btn" onclick="exec('camera')">📷 Camera</button>
                <button class="btn" onclick="exec('record')">🎥 Video</button>
            </div>
        </div>
        <div class="panel">
            <h2>Shell Command</h2>
            <div class="input-row">
                <input type="text" id="shellCmd" placeholder="Shell command">
                <button onclick="exec('shell', document.getElementById('shellCmd').value)">Execute</button>
            </div>
        </div>
    </div>
    
    <div id="settingsPage" class="page">
        <div class="panel">
            <h2>Information</h2>
            <div class="btn-grid">
                <button class="btn" onclick="fetchInfo()">📱 Device Info</button>
                <button class="btn" onclick="exec('battery')">🔋 Battery</button>
                <button class="btn" onclick="exec('cpu')">🧠 CPU</button>
                <button class="btn" onclick="exec('memory')">💾 Memory</button>
                <button class="btn" onclick="exec('storage')">💿 Storage</button>
                <button class="btn" onclick="exec('applist')">📋 Apps</button>
            </div>
        </div>
        <div class="panel">
            <h2>Clipboard</h2>
            <div class="input-row">
                <input type="text" id="clipboardText" placeholder="Text to set">
                <button onclick="exec('clipboard_set', document.getElementById('clipboardText').value)">Set</button>
                <button onclick="exec('clipboard_get')">Get</button>
            </div>
        </div>
    </div>
    
    <div class="panel">
        <h2>Console</h2>
        <div class="output" id="output">Gateway ready.</div>
    </div>
</div>

<script>
    const output = document.getElementById('output');
    let autoRefresh = null;
    
    function log(msg) { output.textContent = `[${new Date().toLocaleTimeString()}] ${msg}\n` + output.textContent; }
    function toast(msg) { const t = document.createElement('div'); t.className='toast'; t.textContent=msg; document.body.appendChild(t); setTimeout(()=>t.remove(),3000); }
    
    async function exec(cmd, args='') {
        try {
            const res = await fetch('/api/command', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({cmd, args}) });
            const data = await res.json();
            log(`> ${cmd} ${args}\n  ${data.result}`);
            toast(`${cmd} executed`);
        } catch(e) { log(`Error: ${e.message}`); }
    }
    
    function execTap() { exec('tap', `${document.getElementById('tapX').value} ${document.getElementById('tapY').value}`); }
    function execText() { exec('text', document.getElementById('textInput').value); }
    function refreshScreen() { document.getElementById('screenImg').src = '/api/screen?' + Date.now(); }
    function startAutoRefresh() { if(autoRefresh) clearInterval(autoRefresh); autoRefresh = setInterval(refreshScreen, 2000); toast('Auto refresh started'); }
    function stopAutoRefresh() { if(autoRefresh) { clearInterval(autoRefresh); autoRefresh = null; toast('Auto refresh stopped'); } }
    
    async function fetchInfo() {
        const res = await fetch('/api/status'); const data = await res.json();
        log(`Device: ${data.info}\nBattery: ${data.battery}\nMemory: ${data.memory}`);
    }
    
    async function loadStatus() {
        try {
            const res = await fetch('/api/status'); const data = await res.json();
            document.getElementById('status').innerHTML = data.status === 'online' ? '● Online' : '○ Offline';
            document.getElementById('device').textContent = data.info.split('\n')[0] || '-';
            const level = data.battery.match(/level:\s*(\d+)/);
            document.getElementById('battery').textContent = level ? level[1]+'%' : '-';
            document.getElementById('clients').textContent = data.connections || 0;
        } catch(e) {}
    }
    
    document.querySelectorAll('.nav-btn').forEach(btn => btn.addEventListener('click', ()=>{
        document.querySelectorAll('.nav-btn').forEach(b=>b.classList.remove('active'));
        document.querySelectorAll('.page').forEach(p=>p.classList.remove('active'));
        btn.classList.add('active');
        document.getElementById(btn.dataset.page+'Page').classList.add('active');
    }));
    
    loadStatus(); setInterval(loadStatus, 5000);
</script>
</body>
</html>
HTML
echo ""

echo "[7/8] Creating start script..."
cat > ~/phonegate/start.sh << 'START'
#!/data/data/com.termux/files/usr/bin/bash
cd ~/phonegate
echo "Starting Phone Gateway v6..."
mkdir -p ~/.phonegate
exec node server.js
START
chmod +x ~/phonegate/start.sh

echo "[8/8] Finalizing..."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "                    ✅ INSTALLATION COMPLETE v6"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "▶ START GATEWAY:"
echo "   cd ~/phonegate && ./start.sh"
echo ""
echo "▶ FEATURES:"
echo "   • 50+ commands covering all phone functions"
echo "   • Live screen casting with auto-refresh"
echo "   • Tabbed interface: Control, Screen, Advanced, Settings"
echo "   • Real-time connection logs"
echo "   • No root required (Shizuku)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
