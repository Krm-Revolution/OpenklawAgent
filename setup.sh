#!/data/data/com.termux/files/usr/bin/bash
export DEBIAN_FRONTEND=noninteractive
export DPKG_FORCE=confold
export APT_LISTCHANGES_FRONTEND=none
export LANG=C
export LC_ALL=C

clear
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                                                              ║"
echo "║         🤖 REMOTE PHONE CONTROL SYSTEM AUTO-INSTALLER        ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

AUTO_INSTALL=true
START_SERVER=true
SETUP_SHIZUKU=true
INSTALL_DEPS=true
CONFIGURE_NETWORK=true
ENABLE_HOTSPOT=true

echo "🚀 Starting fully automated installation..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$INSTALL_DEPS" = true ]; then
    echo "📦 [1/8] Installing all dependencies automatically..."
    pkg update -y -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" </dev/null 2>&1 || true
    for pkg in curl nodejs git nmap openssl android-tools which termux-api termux-tools iproute2 jq net-tools; do
        echo "   Installing $pkg..."
        pkg install -y $pkg </dev/null 2>&1 || true
    done
    echo "✅ All dependencies installed"
fi

if [ "$CONFIGURE_NETWORK" = true ]; then
    echo ""
    echo "🌐 [2/8] Configuring network settings..."
    if ! grep -q "NODE_OPTIONS=--dns-result-order=ipv4first" ~/.bashrc 2>/dev/null; then
        echo "export NODE_OPTIONS=--dns-result-order=ipv4first" >> ~/.bashrc
    fi
    export NODE_OPTIONS=--dns-result-order=ipv4first
    
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
    echo "✅ Network optimized"
fi

echo ""
echo "📂 [3/8] Setting up storage access..."
if [ ! -d "$HOME/storage" ]; then
    echo "y" | termux-setup-storage >/dev/null 2>&1 || true
    sleep 2
fi
echo "✅ Storage configured"

if [ "$SETUP_SHIZUKU" = true ]; then
    echo ""
    echo "🔒 [4/8] Auto-configuring Shizuku integration..."
    SHIZUKU_DIR="$HOME/storage/shared/Shizuku"
    mkdir -p "$SHIZUKU_DIR" 2>/dev/null || true
    
    if [ ! -f "$SHIZUKU_DIR/rish_shizuku.dex" ]; then
        echo "⚠️  rish_shizuku.dex not found. Downloading..."
        curl -L -o "$SHIZUKU_DIR/rish_shizuku.dex" "https://github.com/RikkaApps/Shizuku/releases/latest/download/rish_shizuku.dex" 2>/dev/null || {
            echo "⚠️  Auto-download failed. Please export from Shizuku app manually."
        }
    fi
    
    if [ -f "$SHIZUKU_DIR/rish_shizuku.dex" ]; then
        cat > "$SHIZUKU_DIR/copy.sh" << 'SHIZUKU_EOF'
#!/data/data/com.termux/files/usr/bin/bash
BASEDIR=$( dirname "${0}" )
BIN=/data/data/com.termux/files/usr/bin
HOME=/data/data/com.termux/files/home
DEX="${BASEDIR}/rish_shizuku.dex"
if [ ! -f "${DEX}" ]; then exit 1; fi
ARCH=$(getprop ro.product.cpu.abi 2>/dev/null || echo "arm64-v8a")
case "$ARCH" in arm64*) LIB_ARCH="arm64";; armeabi*) LIB_ARCH="arm";; x86_64*) LIB_ARCH="x86_64";; x86*) LIB_ARCH="x86";; *) LIB_ARCH="arm64";; esac
tee "${BIN}/shizuku" > /dev/null << EOF
#!/data/data/com.termux/files/usr/bin/bash
ports=\$( nmap -sT -p30000-50000 --open localhost 2>/dev/null | grep "open" | cut -f1 -d/ )
for port in \${ports}; do
  result=\$( adb connect "localhost:\${port}" 2>/dev/null )
  if [[ "\$result" =~ "connected" || "\$result" =~ "already" ]]; then
    adb shell "\$( adb shell pm path moe.shizuku.privileged.api | sed 's/^package://;s/base\\\\.apk/lib\\\\/${LIB_ARCH}\\\\/libshizuku\\\\.so/' )"
    adb shell settings put global adb_wifi_enabled 0
    exit 0
  fi
done
echo "ERROR: Enable wireless debugging in developer options"
exit 1
EOF
tee "${BIN}/rish" > /dev/null << EOF
#!/data/data/com.termux/files/usr/bin/bash
[ -z "\$RISH_APPLICATION_ID" ] && export RISH_APPLICATION_ID="com.termux"
/system/bin/app_process -Djava.class.path="${HOME}/rish_shizuku.dex" /system/bin --nice-name=rish rikka.shizuku.shell.ShizukuShellLoader "\${@}"
EOF
chmod +x "${BIN}/shizuku" "${BIN}/rish"
cp -f "${DEX}" "${HOME}/rish_shizuku.dex"
chmod -w "${HOME}/rish_shizuku.dex"
SHIZUKU_EOF
        chmod +x "$SHIZUKU_DIR/copy.sh"
        bash "$SHIZUKU_DIR/copy.sh" </dev/null 2>/dev/null && echo "✅ Shizuku configured" || echo "⚠️  Shizuku setup incomplete"
    fi
fi

echo ""
echo "📱 [5/8] Creating phone control system..."
cat > ~/phone_control.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
CMD="$1"
shift
run_cmd() {
  if command -v rish &>/dev/null; then rish -c "$@" 2>/dev/null
  elif command -v adb &>/dev/null && adb get-state 1>/dev/null 2>&1; then adb shell "$@" 2>/dev/null
  else echo "❌ Shizuku not connected"; exit 1; fi
}
case "$CMD" in
  screenshot) run_cmd "screencap -p '${1:-/sdcard/screenshot.png}'" ;;
  open-app) run_cmd "monkey -p $1 1" 2>/dev/null ;;
  youtube-search) QUERY=$(echo "$*" | sed 's/ /+/g'); run_cmd "am start -a android.intent.action.VIEW -d 'https://www.youtube.com/results?search_query=$QUERY'" ;;
  open-url) run_cmd "am start -a android.intent.action.VIEW -d '$1'" ;;
  wifi) if [ "$1" = "on" ]; then run_cmd "svc wifi enable"; else run_cmd "svc wifi disable"; fi ;;
  hotspot) if [ "$1" = "on" ]; then run_cmd "svc wifi disable; cmd wifi start-softap"; else run_cmd "cmd wifi stop-softap"; fi ;;
  bluetooth) if [ "$1" = "on" ]; then run_cmd "svc bluetooth enable"; else run_cmd "svc bluetooth disable"; fi ;;
  nfc) if [ "$1" = "on" ]; then run_cmd "svc nfc enable"; else run_cmd "svc nfc disable"; fi ;;
  airplane) if [ "$1" = "on" ]; then run_cmd "settings put global airplane_mode_on 1; am broadcast -a android.intent.action.AIRPLANE_MODE"; else run_cmd "settings put global airplane_mode_on 0; am broadcast -a android.intent.action.AIRPLANE_MODE"; fi ;;
  mobile-data) if [ "$1" = "on" ]; then run_cmd "svc data enable"; else run_cmd "svc data disable"; fi ;;
  location) if [ "$1" = "on" ]; then run_cmd "settings put secure location_mode 3"; else run_cmd "settings put secure location_mode 0"; fi ;;
  battery) run_cmd "dumpsys battery" | grep -E "level|temperature|voltage|status" ;;
  battery-saver) if [ "$1" = "on" ]; then run_cmd "settings put global low_power 1"; else run_cmd "settings put global low_power 0"; fi ;;
  brightness) run_cmd "settings put system screen_brightness $1" ;;
  volume) run_cmd "media volume --stream $1 --set $2" ;;
  tap) run_cmd "input tap $1 $2" ;;
  swipe) run_cmd "input swipe $1 $2 $3 $4 ${5:-500}" ;;
  text) run_cmd "input text '$*'" ;;
  key) run_cmd "input keyevent $1" ;;
  home) run_cmd "input keyevent 3" ;;
  back) run_cmd "input keyevent 4" ;;
  recent) run_cmd "input keyevent 187" ;;
  power) run_cmd "input keyevent 26" ;;
  menu) run_cmd "input keyevent 82" ;;
  volume-up) run_cmd "input keyevent 24" ;;
  volume-down) run_cmd "input keyevent 25" ;;
  mute) run_cmd "input keyevent 164" ;;
  play-pause) run_cmd "input keyevent 85" ;;
  next) run_cmd "input keyevent 87" ;;
  previous) run_cmd "input keyevent 88" ;;
  screen-on) run_cmd "input keyevent 224" ;;
  screen-off) run_cmd "input keyevent 223" ;;
  camera) run_cmd "input keyevent 27" ;;
  notification) run_cmd "cmd statusbar expand-notifications" ;;
  quick-settings) run_cmd "cmd statusbar expand-settings" ;;
  sleep) run_cmd "input keyevent 26" ;;
  wake) run_cmd "input keyevent 224; input keyevent 82" ;;
  reboot) run_cmd "reboot" ;;
  lock) run_cmd "am start -a android.app.action.SET_NEW_PASSWORD" ;;
  device-info) run_cmd "getprop ro.product.model; getprop ro.build.version.release; getprop ro.product.manufacturer" ;;
  memory) run_cmd "dumpsys meminfo" | grep -E "Total RAM|Free RAM" ;;
  storage) run_cmd "df -h /data" ;;
  processes) run_cmd "ps -A | head -30" ;;
  kill-app) run_cmd "am force-stop $1" ;;
  uninstall-app) run_cmd "pm uninstall $1" ;;
  list-apps) run_cmd "pm list packages -3 | cut -d: -f2" ;;
  ui-dump) 
    run_cmd "uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1"
    node -e "const fs=require('fs');try{const x=fs.readFileSync('/sdcard/window_dump.xml','utf8');const r=/(?:text|content-desc)=\"([^\"]+)\"[^>]*bounds=\"(\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\])\"/g;let m;while((m=r.exec(x))!==null){if(m[1].trim()!=='')console.log(m[2]+' '+m[1]);}}catch(e){}" 2>/dev/null
    ;;
  shell) run_cmd "$*" ;;
  *) echo "Unknown command: $CMD" ;;
esac
EOF
chmod +x ~/phone_control.sh
echo "✅ Phone control ready"

echo ""
echo "🌐 [6/8] Building web control panel..."
mkdir -p ~/phone_server
cat > ~/phone_server/package.json << 'EOF'
{"name":"phone-control","version":"1.0.0","main":"server.js","dependencies":{"express":"latest","socket.io":"latest"}}
EOF

cat > ~/phone_server/server.js << 'EOFJS'
const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const { exec } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const app = express();
const server = http.createServer(app);
const io = socketIo(server, { cors: { origin: "*", methods: ["GET", "POST"] } });
const PORT = 3000;

app.use(express.json());
app.use(express.static(__dirname));

const LOG_FILE = path.join(os.homedir(), 'phone_control.log');
const HISTORY_FILE = path.join(os.homedir(), 'command_history.json');
const CONNECTIONS_FILE = path.join(os.homedir(), 'connected_devices.json');

let connectedDevices = new Map();
let deviceCounter = 0;

try { if(fs.existsSync(CONNECTIONS_FILE)) JSON.parse(fs.readFileSync(CONNECTIONS_FILE,'utf8')).forEach(d=>connectedDevices.set(d.id,d)); } catch(e) {}

function saveConnectedDevices() {
  fs.writeFileSync(CONNECTIONS_FILE, JSON.stringify(Array.from(connectedDevices.values()), null, 2));
}

function log(message, type='info', deviceInfo=null) {
  const entry = { timestamp: new Date().toISOString(), type, message, device: deviceInfo ? { ip: deviceInfo.ip } : null };
  fs.appendFileSync(LOG_FILE, JSON.stringify(entry) + '\n');
  io.emit('log', entry);
}

function executeCommand(cmd, deviceInfo) {
  return new Promise((resolve) => {
    const command = `bash ~/phone_control.sh ${cmd}`;
    log(`[${deviceInfo ? deviceInfo.ip : 'local'}] ${cmd}`, 'command', deviceInfo);
    exec(command, { shell: '/data/data/com.termux/files/usr/bin/bash', timeout: 30000 }, (error, stdout, stderr) => {
      const result = error ? `Error: ${error.message}` : (stdout || stderr || 'Done');
      log(`Result: ${result.slice(0, 200)}`, error ? 'error' : 'success', deviceInfo);
      let history = [];
      try { history = JSON.parse(fs.readFileSync(HISTORY_FILE,'utf8')); } catch(e) {}
      history.unshift({ timestamp: new Date().toISOString(), command: cmd, result: result.slice(0, 200), device: deviceInfo ? deviceInfo.ip : 'local' });
      fs.writeFileSync(HISTORY_FILE, JSON.stringify(history.slice(0, 100), null, 2));
      resolve(result);
    });
  });
}

async function aiProcessCommand(userInput) {
  try {
    const res = await fetch('https://text.pollinations.ai/', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        messages: [{ role: 'system', content: 'Convert to phone_control.sh command. Available: screenshot, open-app, open-url, youtube-search, wifi, hotspot, bluetooth, nfc, airplane, mobile-data, location, battery, battery-saver, brightness, volume, tap, swipe, text, key, home, back, recent, power, menu, volume-up, volume-down, mute, play-pause, next, previous, screen-on, screen-off, camera, notification, quick-settings, sleep, wake, reboot, lock, device-info, memory, storage, processes, kill-app, uninstall-app, list-apps, ui-dump, shell. Respond ONLY with command.' }, { role: 'user', content: userInput }],
        model: 'openai', temperature: 0.1
      })
    });
    return (await res.text()).trim();
  } catch(e) { return null; }
}

function getHotspotIP() {
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal) {
        if (name.includes('wlan') || name.includes('ap') || name.includes('rmnet')) return iface.address;
      }
    }
  }
  return Object.values(interfaces).flat().find(i => i.family === 'IPv4' && !i.internal)?.address || '0.0.0.0';
}

app.get('/', (req, res) => res.sendFile(path.join(__dirname, 'index.html')));
app.get('/api/logs', (req, res) => {
  try { res.json(fs.readFileSync(LOG_FILE,'utf8').split('\n').filter(l=>l).map(JSON.parse).slice(-200)); } catch(e) { res.json([]); }
});
app.get('/api/device', async (req, res) => {
  res.json({ info: await executeCommand('device-info'), battery: await executeCommand('battery'), memory: await executeCommand('memory') });
});
app.get('/api/gateway', (req, res) => {
  const ip = getHotspotIP();
  res.json({ ip, url: `http://${ip}:${PORT}`, port: PORT });
});
app.get('/api/connections', (req, res) => res.json(Array.from(connectedDevices.values())));
app.post('/api/command', async (req, res) => {
  const deviceInfo = { ip: req.ip.replace('::ffff:', ''), userAgent: req.get('User-Agent') };
  res.json({ success: true, result: await executeCommand(req.body.command, deviceInfo) });
});
app.post('/api/ai', async (req, res) => {
  const deviceInfo = { ip: req.ip.replace('::ffff:', ''), userAgent: req.get('User-Agent') };
  const cmd = await aiProcessCommand(req.body.prompt);
  if (cmd && !cmd.includes('sorry')) {
    res.json({ success: true, command: cmd, result: await executeCommand(cmd, deviceInfo) });
  } else {
    res.json({ success: false, message: 'Cannot parse command' });
  }
});
app.post('/api/search', async (req, res) => {
  try {
    const response = await fetch(`https://text.pollinations.ai/${encodeURIComponent(req.body.query)}?model=search`);
    res.json({ success: true, result: await response.text() });
  } catch(e) { res.json({ success: false }); }
});

io.on('connection', (socket) => {
  const deviceInfo = {
    id: `device_${++deviceCounter}_${Date.now()}`,
    ip: socket.handshake.address.replace('::ffff:', ''),
    userAgent: socket.handshake.headers['user-agent'],
    connectedAt: new Date().toISOString(),
    socketId: socket.id
  };
  connectedDevices.set(deviceInfo.id, deviceInfo);
  saveConnectedDevices();
  log(`📱 Device connected from ${deviceInfo.ip}`, 'system', deviceInfo);
  console.log(`📱 [${new Date().toLocaleTimeString()}] Device connected: ${deviceInfo.ip}`);
  io.emit('devicesUpdate', Array.from(connectedDevices.values()));
  
  socket.on('disconnect', () => {
    const device = connectedDevices.get(deviceInfo.id);
    if (device) {
      device.disconnectedAt = new Date().toISOString();
      log(`📱 Device disconnected from ${device.ip}`, 'system', device);
      console.log(`📱 [${new Date().toLocaleTimeString()}] Device disconnected: ${device.ip}`);
      connectedDevices.delete(deviceInfo.id);
      saveConnectedDevices();
      io.emit('devicesUpdate', Array.from(connectedDevices.values()));
    }
  });
  
  socket.on('getLogs', () => {
    try { socket.emit('logs', fs.readFileSync(LOG_FILE,'utf8').split('\n').filter(l=>l).map(JSON.parse).slice(-100)); } catch(e) {}
  });
  
  socket.on('command', async (cmd) => {
    socket.emit('commandResult', { command: cmd, result: await executeCommand(cmd, deviceInfo) });
  });
  
  socket.on('getGateway', () => socket.emit('gatewayInfo', getHotspotIP() ? { url: `http://${getHotspotIP()}:${PORT}` } : { url: 'Not available' }));
});

server.listen(PORT, '0.0.0.0', () => {
  const ip = getHotspotIP();
  log(`🌐 Server started - Gateway: http://${ip}:${PORT}`, 'system');
  console.log(`\n✅ Server running at http://${ip}:${PORT}\n`);
});
EOFJS

cat > ~/phone_server/index.html << 'EOFHTML'
<!DOCTYPE html>
<html><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=yes">
<title>📱 Phone Control</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:linear-gradient(135deg,#1a1a2e 0%,#16213e 50%,#0f3460 100%);min-height:100vh;padding:16px;color:#fff}
.container{max-width:1400px;margin:0 auto}
.gateway-banner{background:linear-gradient(135deg,#00b4db,#0083b0);border-radius:16px;padding:20px;margin-bottom:20px;text-align:center}
.gateway-url{font-size:28px;font-weight:bold;font-family:monospace;background:rgba(0,0,0,0.3);padding:12px 24px;border-radius:12px;display:inline-block;margin:10px 0}
.copy-btn{background:rgba(255,255,255,0.2);border:1px solid rgba(255,255,255,0.3);color:#fff;padding:8px 16px;border-radius:8px;cursor:pointer;margin-left:10px}
h1{font-size:24px;margin-bottom:16px;display:flex;align-items:center;gap:8px}
h2{font-size:18px;margin-bottom:12px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:16px;margin-bottom:16px}
.card{background:rgba(255,255,255,0.1);backdrop-filter:blur(10px);border-radius:16px;padding:16px;border:1px solid rgba(255,255,255,0.1)}
.btn-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(80px,1fr));gap:8px}
button{background:rgba(255,255,255,0.15);border:1px solid rgba(255,255,255,0.2);color:#fff;padding:10px 12px;border-radius:10px;font-size:13px;font-weight:500;cursor:pointer;transition:all 0.2s;display:flex;flex-direction:column;align-items:center;gap:4px}
button:hover{background:rgba(255,255,255,0.25);transform:translateY(-2px)}
button svg{width:24px;height:24px;fill:currentColor}
.input-group{display:flex;gap:8px;margin-top:12px}
input{flex:1;padding:10px 12px;border:none;border-radius:10px;background:rgba(255,255,255,0.15);color:#fff;font-size:14px;border:1px solid rgba(255,255,255,0.2)}
input::placeholder{color:rgba(255,255,255,0.5)}
.log-container{background:rgba(0,0,0,0.3);border-radius:10px;padding:12px;max-height:300px;overflow-y:auto;font-family:monospace;font-size:12px}
.log-entry{padding:4px 0;border-bottom:1px solid rgba(255,255,255,0.1)}
.log-time{color:#64b5f6}.log-success{color:#81c784}.log-error{color:#e57373}.log-system{color:#ffd54f}.log-command{color:#ba68c8}
.devices-panel{background:rgba(0,0,0,0.3);border-radius:10px;padding:12px;margin-bottom:16px}
.device-item{display:flex;align-items:center;gap:8px;padding:8px;background:rgba(255,255,255,0.05);border-radius:8px;margin-bottom:4px}
.device-online{width:10px;height:10px;border-radius:50%;background:#4caf50;animation:pulse 2s infinite}
.status-bar{display:flex;gap:12px;margin-bottom:16px;flex-wrap:wrap}
.status-item{background:rgba(255,255,255,0.1);backdrop-filter:blur(10px);padding:8px 16px;border-radius:20px;display:flex;align-items:center;gap:8px}
.connection-dot{width:10px;height:10px;border-radius:50%;background:#4ade80;animation:pulse 2s infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:0.5}}
.ai-section{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%)}
.search-section{background:linear-gradient(135deg,#f093fb 0%,#f5576c 100%)}
</style>
</head><body>
<div class="container">
<div class="gateway-banner"><h2 style="margin-bottom:8px">🌐 Gateway Access URL</h2><div><span class="gateway-url" id="gatewayUrl">Loading...</span><button class="copy-btn" onclick="copyGatewayUrl()">📋 Copy</button></div><p style="margin-top:12px;opacity:0.9">Connect to this hotspot and open this URL</p></div>
<div class="devices-panel"><h3>📱 Connected Devices <span id="deviceCount">(0)</span></h3><div id="devicesList"><div class="device-item" style="justify-content:center;opacity:0.7">No devices connected</div></div></div>
<h1><svg width="32" height="32" viewBox="0 0 24 24" fill="currentColor"><path d="M17 1.01L7 1c-1.1 0-2 .9-2 2v18c0 1.1.9 2 2 2h10c1.1 0 2-.9 2-2V3c0-1.1-.9-1.99-2-1.99zM17 19H7V5h10v14z"/></svg>Remote Phone Control</h1>
<div class="status-bar"><div class="status-item"><span class="connection-dot"></span><span id="connectionStatus">Connected</span></div><div class="status-item"><span id="deviceModel">Loading...</span></div><div class="status-item"><span id="batteryLevel">🔋 --%</span></div></div>
<div class="grid">
<div class="card ai-section"><h2>🤖 AI Assistant</h2><div class="input-group"><input type="text" id="aiInput" placeholder="e.g., open chrome"><button onclick="sendAI()">Send</button></div><div id="aiResult" style="margin-top:12px;font-size:14px"></div></div>
<div class="card search-section"><h2>🔍 Web Search</h2><div class="input-group"><input type="text" id="searchInput" placeholder="Search..."><button onclick="webSearch()">Search</button></div><div id="searchResult" style="margin-top:12px;max-height:150px;overflow-y:auto;font-size:13px"></div></div>
</div>
<div class="grid">
<div class="card"><h2>📱 Navigation</h2><div class="btn-grid">
<button onclick="send('home')"><svg viewBox="0 0 24 24"><path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"/></svg>Home</button>
<button onclick="send('back')"><svg viewBox="0 0 24 24"><path d="M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z"/></svg>Back</button>
<button onclick="send('recent')"><svg viewBox="0 0 24 24"><path d="M4 8h4V4H4v4zm6 12h4v-4h-4v4zm-6 0h4v-4H4v4zm0-6h4v-4H4v4zm6 0h4v-4h-4v4zm6-10v4h4V4h-4zm-6 4h4V4h-4v4zm6 6h4v-4h-4v4zm0 6h4v-4h-4v4z"/></svg>Recent</button>
<button onclick="send('menu')"><svg viewBox="0 0 24 24"><path d="M3 18h18v-2H3v2zm0-5h18v-2H3v2zm0-7v2h18V6H3z"/></svg>Menu</button>
</div></div>
<div class="card"><h2>🔊 Media</h2><div class="btn-grid">
<button onclick="send('volume-up')"><svg viewBox="0 0 24 24"><path d="M3 9v6h4l5 5V4L7 9H3z"/></svg>Vol+</button>
<button onclick="send('volume-down')"><svg viewBox="0 0 24 24"><path d="M18.5 12c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02z"/></svg>Vol-</button>
<button onclick="send('mute')"><svg viewBox="0 0 24 24"><path d="M16.5 12c0-1.77-1.02-3.29-2.5-4.03v2.21l2.45 2.45c.03-.2.05-.41.05-.63z"/></svg>Mute</button>
<button onclick="send('play-pause')"><svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>Play</button>
<button onclick="send('next')"><svg viewBox="0 0 24 24"><path d="M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z"/></svg>Next</button>
<button onclick="send('previous')"><svg viewBox="0 0 24 24"><path d="M6 6h2v12H6zm3.5 6l8.5 6V6z"/></svg>Prev</button>
</div></div>
</div>
<div class="grid">
<div class="card"><h2>⚡ Power</h2><div class="btn-grid">
<button onclick="send('power')"><svg viewBox="0 0 24 24"><path d="M13 3h-2v10h2V3zm4.83 2.17l-1.42 1.42C17.99 7.86 19 9.81 19 12c0 3.87-3.13 7-7 7s-7-3.13-7-7c0-2.19 1.01-4.14 2.59-5.42L6.17 5.17C4.23 6.82 3 9.26 3 12c0 4.97 4.03 9 9 9s9-4.03 9-9c0-2.74-1.23-5.18-3.17-6.83z"/></svg>Power</button>
<button onclick="send('screen-on')"><svg viewBox="0 0 24 24"><path d="M12 7V3H2v18h20V7H12z"/></svg>Screen On</button>
<button onclick="send('screen-off')"><svg viewBox="0 0 24 24"><path d="M20 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2z"/></svg>Screen Off</button>
<button onclick="send('lock')"><svg viewBox="0 0 24 24"><path d="M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2z"/></svg>Lock</button>
<button onclick="send('sleep')"><svg viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z"/></svg>Sleep</button>
<button onclick="send('wake')"><svg viewBox="0 0 24 24"><path d="M20 12c0-4.41-3.59-8-8-8s-8 3.59-8 8 3.59 8 8 8 8-3.59 8-8z"/></svg>Wake</button>
</div></div>
<div class="card"><h2>📶 Connectivity</h2><div class="btn-grid">
<button onclick="send('wifi on')"><svg viewBox="0 0 24 24"><path d="M1 9l2 2c4.97-4.97 13.03-4.97 18 0l2-2C16.44 3.9 7.56 3.9 1 9z"/></svg>WiFi On</button>
<button onclick="send('wifi off')"><svg viewBox="0 0 24 24"><path d="M1 9l2 2c4.97-4.97 13.03-4.97 18 0l2-2C16.44 3.9 7.56 3.9 1 9z"/></svg>WiFi Off</button>
<button onclick="send('hotspot on')"><svg viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z"/></svg>Hotspot On</button>
<button onclick="send('hotspot off')"><svg viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z"/></svg>Hotspot Off</button>
<button onclick="send('bluetooth on')"><svg viewBox="0 0 24 24"><path d="M17.71 7.71L12 2h-1v7.59L6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 11 14.41V22h1l5.71-5.71-4.3-4.29 4.3-4.29z"/></svg>BT On</button>
<button onclick="send('bluetooth off')"><svg viewBox="0 0 24 24"><path d="M17.71 7.71L12 2h-1v7.59L6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 11 14.41V22h1l5.71-5.71-4.3-4.29 4.3-4.29z"/></svg>BT Off</button>
</div></div>
</div>
<div class="card"><h2>📝 Command Log</h2><div class="input-group"><input type="text" id="customCommand" placeholder="Enter command..."><button onclick="send(document.getElementById('customCommand').value)">Execute</button></div><div class="log-container" id="logContainer"></div></div>
</div>
<script src="/socket.io/socket.io.js"></script>
<script>
const socket=io();const logContainer=document.getElementById('logContainer');
socket.on('connect',()=>{document.getElementById('connectionStatus').textContent='Connected';socket.emit('getLogs');socket.emit('getGateway');loadDeviceInfo()});
socket.on('log',log=>{addLog(log)});
socket.on('logs',logs=>{logContainer.innerHTML='';logs.reverse().forEach(addLog)});
socket.on('commandResult',d=>{addLog({timestamp:new Date().toISOString(),type:'success',message:`${d.command}: ${d.result}`})});
socket.on('gatewayInfo',info=>{document.getElementById('gatewayUrl').textContent=info.url});
socket.on('devicesUpdate',devices=>{document.getElementById('deviceCount').textContent=`(${devices.length})`;document.getElementById('devicesList').innerHTML=devices.length?devices.map(d=>`<div class="device-item"><span class="device-online"></span><span style="flex:1">${d.ip}</span><span style="font-size:11px;opacity:0.5">${new Date(d.connectedAt).toLocaleTimeString()}</span></div>`).join(''):'<div class="device-item" style="justify-content:center;opacity:0.7">No devices connected</div>'});
function addLog(l){const d=document.createElement('div');d.className='log-entry';d.innerHTML=`<span class="log-time">[${new Date(l.timestamp).toLocaleTimeString()}]</span> <span class="log-${l.type}">${l.device?`[${l.device.ip}] `:''}${l.message}</span>`;logContainer.appendChild(d);logContainer.scrollTop=logContainer.scrollHeight}
function send(c){socket.emit('command',c)}
async function loadDeviceInfo(){try{const r=await fetch('/api/device');const d=await r.json();const i=d.info.split('\n');document.getElementById('deviceModel').textContent=`${i[2]||'Android'} ${i[1]||''}`;const b=d.battery.match(/level: (\d+)/);if(b)document.getElementById('batteryLevel').textContent=`🔋 ${b[1]}%`}catch(e){}}
function copyGatewayUrl(){navigator.clipboard.writeText(document.getElementById('gatewayUrl').textContent);alert('Copied!')}
async function sendAI(){const i=document.getElementById('aiInput');const p=i.value.trim();if(!p)return;addLog({timestamp:new Date().toISOString(),type:'system',message:`AI: ${p}`});try{const r=await fetch('/api/ai',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({prompt:p})});const d=await r.json();document.getElementById('aiResult').innerHTML=d.success?`✅ ${d.command}<br>📱 ${d.result}`:`❌ ${d.message}`}catch(e){document.getElementById('aiResult').innerHTML='❌ Error'}i.value=''}
async function webSearch(){const i=document.getElementById('searchInput');const q=i.value.trim();if(!q)return;addLog({timestamp:new Date().toISOString(),type:'system',message:`Search: ${q}`});try{const r=await fetch('/api/search',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({query:q})});const d=await r.json();document.getElementById('searchResult').innerHTML=d.result}catch(e){document.getElementById('searchResult').innerHTML='Search failed'}i.value=''}
setInterval(loadDeviceInfo,30000);loadDeviceInfo()
</script>
</body></html>
EOFHTML

echo "✅ Web panel built"

echo ""
echo "🔧 [7/8] Creating auto-start service..."
mkdir -p ~/.termux/boot
cat > ~/.termux/boot/start-phone-server << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
cd ~/phone_server
npm install --silent express socket.io 2>/dev/null
node server.js > /dev/null 2>&1 &
echo "Phone control server started"
EOF
chmod +x ~/.termux/boot/start-phone-server

cat > ~/view_connections.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
echo "📱 Connected Devices Log"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -f ~/connected_devices.json ]; then
    cat ~/connected_devices.json | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));if(d.length===0){console.log('No devices')}else{d.forEach((x,i)=>{console.log(\`\${i+1}. IP: \${x.ip}\`);console.log(\`   Connected: \${new Date(x.connectedAt).toLocaleString()}\`);if(x.disconnectedAt)console.log(\`   Disconnected: \${new Date(x.disconnectedAt).toLocaleString()}\`);console.log('')})}"
else
    echo "No connections yet"
fi
echo ""
echo "📋 Live Log:"
tail -f ~/phone_control.log | grep --line-buffered "Device"
EOF
chmod +x ~/view_connections.sh

echo "✅ Auto-start configured"

echo ""
echo "🚀 [8/8] Installing Node modules and starting server..."
cd ~/phone_server
npm install --silent express socket.io 2>/dev/null

if [ "$ENABLE_HOTSPOT" = true ]; then
    echo ""
    echo "📶 Enabling hotspot automatically..."
    ~/phone_control.sh hotspot on 2>/dev/null || true
    sleep 3
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ AUTO-INSTALLATION COMPLETE!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

GATEWAY_IP=$(ip route get 1 2>/dev/null | grep -oP 'src \K\S+' | head -1)
if [ -z "$GATEWAY_IP" ]; then
    GATEWAY_IP=$(ifconfig wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}')
fi
if [ -z "$GATEWAY_IP" ]; then
    GATEWAY_IP="192.168.43.1"
fi

echo "🌐 ACCESS FROM OTHER DEVICES:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "   📱 Gateway URL: http://$GATEWAY_IP:3000"
echo ""
echo "   📋 Copy this URL and paste it on other devices"
echo "      connected to this phone's hotspot!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 View connected devices:"
echo "   bash ~/view_connections.sh"
echo ""
echo "🔄 Server auto-starts on boot (Termux:Boot required)"
echo ""

if [ "$START_SERVER" = true ]; then
    echo "🚀 Starting server now..."
    echo ""
    node server.js
fi
