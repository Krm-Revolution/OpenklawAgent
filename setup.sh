#!/data/data/com.termux/files/usr/bin/bash
export DEBIAN_FRONTEND=noninteractive
export DPKG_FORCE=confold
export APT_LISTCHANGES_FRONTEND=none
export LANG=C
export LC_ALL=C

echo ""
echo "🤖 Remote Phone Control System Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "📦 Step 1/7: Installing dependencies..."
pkg update -y -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" </dev/null 2>&1 || true
pkg install -y curl nodejs git nmap openssl android-tools which termux-api termux-tools iproute2 </dev/null 2>&1 || true

MISSING=""
for cmd in curl node git nmap adb ip; do
    if ! command -v "$cmd" </dev/null >/dev/null 2>&1; then
        MISSING="$MISSING $cmd"
    fi
done
if [ -n "$MISSING" ]; then
    echo "❌ ERROR: Missing:$MISSING"
    exit 1
fi
echo "✅ Dependencies installed"

echo ""
echo "🔒 Step 2/7: Setting up Shizuku..."
if [ ! -d "$HOME/storage" ]; then
    echo "y" | termux-setup-storage > /dev/null 2>&1 || true
    sleep 3
fi
SHIZUKU_DIR="$HOME/storage/shared/Shizuku"
mkdir -p "$SHIZUKU_DIR" 2>/dev/null || true

cat > "$SHIZUKU_DIR/copy.sh" << 'SHIZUKU_EOF'
#!/data/data/com.termux/files/usr/bin/bash
BASEDIR=$( dirname "${0}" )
BIN=/data/data/com.termux/files/usr/bin
HOME=/data/data/com.termux/files/home
DEX="${BASEDIR}/rish_shizuku.dex"
if [ ! -f "${DEX}" ]; then
  echo "Cannot find ${DEX}"
  exit 1
fi
ARCH=$(getprop ro.product.cpu.abi 2>/dev/null || echo "arm64-v8a")
case "$ARCH" in
  arm64*) LIB_ARCH="arm64" ;;
  armeabi*) LIB_ARCH="arm" ;;
  x86_64*) LIB_ARCH="x86_64" ;;
  x86*) LIB_ARCH="x86" ;;
  *) LIB_ARCH="arm64" ;;
esac
tee "${BIN}/shizuku" > /dev/null << EOF
#!/data/data/com.termux/files/usr/bin/bash
ports=\$( nmap -sT -p30000-50000 --open localhost 2>/dev/null | grep "open" | cut -f1 -d/ )
for port in \${ports}; do
  result=\$( adb connect "localhost:\${port}" 2>/dev/null )
  if [[ "\$result" =~ "connected" || "\$result" =~ "already" ]]; then
    echo "\${result}"
    adb shell "\$( adb shell pm path moe.shizuku.privileged.api | sed 's/^package://;s/base\\\\.apk/lib\\\\/${LIB_ARCH}\\\\/libshizuku\\\\.so/' )"
    adb shell settings put global adb_wifi_enabled 0
    exit 0
  fi
done
echo "ERROR: No port found! Is wireless debugging enabled?"
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

if [ ! -f "$SHIZUKU_DIR/rish_shizuku.dex" ]; then
    echo "❌ rish_shizuku.dex not found in $SHIZUKU_DIR"
    exit 1
fi
bash "$SHIZUKU_DIR/copy.sh" </dev/null && echo "✅ Shizuku scripts installed" || echo "⚠️ Shizuku setup incomplete"

echo ""
echo "🔧 Step 3/7: Network fixes..."
if ! grep -q "NODE_OPTIONS=--dns-result-order=ipv4first" ~/.bashrc 2>/dev/null; then
    echo "export NODE_OPTIONS=--dns-result-order=ipv4first" >> ~/.bashrc
fi
export NODE_OPTIONS=--dns-result-order=ipv4first
echo "✅ Network configured"

echo ""
echo "📡 Step 4/7: Creating phone control system..."
cat > ~/phone_control.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
CMD="$1"
shift
run_cmd() {
  if command -v rish &>/dev/null; then rish -c "$@"
  elif command -v adb &>/dev/null && adb get-state 1>/dev/null 2>&1; then adb shell "$@"
  elif command -v su &>/dev/null; then su -c "$@"
  else echo "❌ Shizuku not connected"; exit 1; fi
}
case "$CMD" in
  screenshot) run_cmd "screencap -p '${1:-/sdcard/screenshot.png}'" ;;
  open-app) run_cmd "monkey -p $1 -c android.intent.category.LAUNCHER 1" 2>/dev/null ;;
  youtube-search) QUERY=$(echo "$*" | sed 's/ /+/g'); run_cmd "am start -a android.intent.action.VIEW -d 'https://www.youtube.com/results?search_query=$QUERY' com.google.android.youtube" ;;
  open-url) run_cmd "am start -a android.intent.action.VIEW -d '$1'" ;;
  wifi) if [ "$1" = "on" ]; then run_cmd "svc wifi enable"; else run_cmd "svc wifi disable"; fi ;;
  hotspot) if [ "$1" = "on" ]; then run_cmd "svc wifi disable; cmd connectivity start-tethering"; else run_cmd "cmd connectivity stop-tethering"; fi ;;
  bluetooth) if [ "$1" = "on" ]; then run_cmd "svc bluetooth enable"; else run_cmd "svc bluetooth disable"; fi ;;
  nfc) if [ "$1" = "on" ]; then run_cmd "svc nfc enable"; else run_cmd "svc nfc disable"; fi ;;
  airplane) if [ "$1" = "on" ]; then run_cmd "settings put global airplane_mode_on 1; am broadcast -a android.intent.action.AIRPLANE_MODE"; else run_cmd "settings put global airplane_mode_on 0; am broadcast -a android.intent.action.AIRPLANE_MODE"; fi ;;
  mobile-data) if [ "$1" = "on" ]; then run_cmd "svc data enable"; else run_cmd "svc data disable"; fi ;;
  location) if [ "$1" = "on" ]; then run_cmd "settings put secure location_mode 3"; else run_cmd "settings put secure location_mode 0"; fi ;;
  battery) run_cmd "dumpsys battery" | grep -E "level|temperature|voltage|status|health|technology" ;;
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
  search) run_cmd "input keyevent 84" ;;
  volume-up) run_cmd "input keyevent 24" ;;
  volume-down) run_cmd "input keyevent 25" ;;
  mute) run_cmd "input keyevent 164" ;;
  play-pause) run_cmd "input keyevent 85" ;;
  next) run_cmd "input keyevent 87" ;;
  previous) run_cmd "input keyevent 88" ;;
  stop) run_cmd "input keyevent 86" ;;
  screen-on) run_cmd "input keyevent 224" ;;
  screen-off) run_cmd "input keyevent 223" ;;
  camera) run_cmd "input keyevent 27" ;;
  call) run_cmd "am start -a android.intent.action.CALL -d tel:$1" ;;
  clipboard-get) run_cmd "cmd clipboard get-text" 2>/dev/null ;;
  clipboard-set) run_cmd "cmd clipboard set-text '$*'" 2>/dev/null ;;
  notification) run_cmd "cmd statusbar expand-notifications" ;;
  quick-settings) run_cmd "cmd statusbar expand-settings" ;;
  sleep) run_cmd "input keyevent 26" ;;
  wake) run_cmd "input keyevent 224; input keyevent 82" ;;
  reboot) run_cmd "reboot" ;;
  recovery) run_cmd "reboot recovery" ;;
  bootloader) run_cmd "reboot bootloader" ;;
  lock) run_cmd "am start -a android.app.action.SET_NEW_PASSWORD" ;;
  device-info) run_cmd "getprop ro.product.model; getprop ro.build.version.release; getprop ro.product.manufacturer" ;;
  memory) run_cmd "dumpsys meminfo" | grep -E "Total RAM|Free RAM|Used RAM" ;;
  storage) run_cmd "df -h /data" ;;
  processes) run_cmd "ps -A | head -30" ;;
  kill-app) run_cmd "am force-stop $1" ;;
  clear-app-data) run_cmd "pm clear $1" ;;
  install-app) run_cmd "pm install -r $1" ;;
  uninstall-app) run_cmd "pm uninstall $1" ;;
  list-apps) run_cmd "pm list packages -3 | cut -d: -f2" ;;
  start-app) run_cmd "am start -n $1" ;;
  ui-dump) 
    run_cmd "uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1"
    node -e "
      const fs = require('fs');
      try {
        const xml = fs.readFileSync('/sdcard/window_dump.xml', 'utf8');
        const regex = /(?:text|content-desc)=\"([^\"]+)\"[^>]*bounds=\"(\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\])\"/g;
        let match;
        while ((match = regex.exec(xml)) !== null) {
          if (match[1].trim() !== '') console.log(match[2] + ' ' + match[1]);
        }
      } catch(e) { console.log('{}'); }
    "
    ;;
  shell) run_cmd "$*" ;;
  *) echo "Unknown command: $CMD" ;;
esac
EOF
chmod +x ~/phone_control.sh
echo "✅ Phone control system created"

echo ""
echo "🌐 Step 5/7: Building web control panel with device tracking..."
mkdir -p ~/phone_server
cat > ~/phone_server/server.js << 'EOF'
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
app.use(express.static(path.join(__dirname, 'public')));

const LOG_FILE = path.join(require('os').homedir(), 'phone_control.log');
const HISTORY_FILE = path.join(require('os').homedir(), 'command_history.json');
const CONNECTIONS_FILE = path.join(require('os').homedir(), 'connected_devices.json');

let connectedDevices = new Map();
let deviceCounter = 0;

function loadConnectedDevices() {
  try {
    if (fs.existsSync(CONNECTIONS_FILE)) {
      const data = JSON.parse(fs.readFileSync(CONNECTIONS_FILE, 'utf8'));
      data.forEach(d => connectedDevices.set(d.id, d));
    }
  } catch(e) {}
}

function saveConnectedDevices() {
  const devices = Array.from(connectedDevices.values());
  fs.writeFileSync(CONNECTIONS_FILE, JSON.stringify(devices, null, 2));
}

loadConnectedDevices();

function log(message, type = 'info', deviceInfo = null) {
  const timestamp = new Date().toISOString();
  const logEntry = { 
    timestamp, 
    type, 
    message,
    device: deviceInfo ? { id: deviceInfo.id, ip: deviceInfo.ip, userAgent: deviceInfo.userAgent } : null
  };
  fs.appendFileSync(LOG_FILE, JSON.stringify(logEntry) + '\n');
  io.emit('log', logEntry);
  return logEntry;
}

function saveHistory(command, result, deviceInfo) {
  let history = [];
  try { history = JSON.parse(fs.readFileSync(HISTORY_FILE, 'utf8')); } catch(e) {}
  history.unshift({ 
    timestamp: new Date().toISOString(), 
    command, 
    result: result.slice(0, 200),
    device: deviceInfo ? deviceInfo.ip : 'local'
  });
  history = history.slice(0, 100);
  fs.writeFileSync(HISTORY_FILE, JSON.stringify(history, null, 2));
}

function executeCommand(cmd, deviceInfo) {
  return new Promise((resolve) => {
    const command = `bash ~/phone_control.sh ${cmd}`;
    log(`[${deviceInfo ? deviceInfo.ip : 'local'}] Executing: ${cmd}`, 'command', deviceInfo);
    exec(command, { shell: '/data/data/com.termux/files/usr/bin/bash', timeout: 30000 }, (error, stdout, stderr) => {
      const result = error ? `Error: ${error.message}` : (stdout || stderr || 'Command executed');
      log(`[${deviceInfo ? deviceInfo.ip : 'local'}] Result: ${result.slice(0, 200)}`, error ? 'error' : 'success', deviceInfo);
      saveHistory(cmd, result, deviceInfo);
      resolve(result);
    });
  });
}

async function aiProcessCommand(userInput) {
  try {
    const aiResponse = await fetch('https://text.pollinations.ai/', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        messages: [
          { role: 'system', content: `You are a phone control AI. Convert user requests into phone_control.sh commands.
Available commands: screenshot, open-app, open-url, youtube-search, wifi, hotspot, bluetooth, nfc, airplane, mobile-data, location, battery, battery-saver, brightness, volume, tap, swipe, text, key, home, back, recent, power, menu, search, volume-up, volume-down, mute, play-pause, next, previous, stop, screen-on, screen-off, camera, call, clipboard-get, clipboard-set, notification, quick-settings, sleep, wake, reboot, recovery, bootloader, lock, device-info, memory, storage, processes, kill-app, clear-app-data, install-app, uninstall-app, list-apps, start-app, ui-dump, shell.
Respond with ONLY the exact command to execute.` },
          { role: 'user', content: userInput }
        ],
        model: 'openai',
        temperature: 0.1
      })
    });
    const data = await aiResponse.text();
    return data.trim();
  } catch(e) {
    return null;
  }
}

async function webSearch(query) {
  try {
    const response = await fetch(`https://text.pollinations.ai/${encodeURIComponent(query)}?model=search`);
    return await response.text();
  } catch(e) {
    return 'Search failed';
  }
}

function getHotspotIP() {
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal) {
        if (name.includes('wlan') || name.includes('rmnet') || name.includes('ap')) return iface.address;
      }
    }
  }
  return Object.values(interfaces).flat().find(i => i.family === 'IPv4' && !i.internal)?.address || '0.0.0.0';
}

function getGatewayInfo() {
  const ip = getHotspotIP();
  return {
    ip: ip,
    gateway: ip,
    url: `http://${ip}:${PORT}`,
    port: PORT,
    hotspot: ip.startsWith('192.168.43.') || ip.startsWith('192.168.42.')
  };
}

app.get('/', (req, res) => res.sendFile(path.join(__dirname, 'public', 'index.html')));
app.get('/api/logs', (req, res) => {
  try {
    const logs = fs.readFileSync(LOG_FILE, 'utf8').split('\n').filter(l => l).map(l => JSON.parse(l));
    res.json(logs.slice(-200));
  } catch(e) { res.json([]); }
});
app.get('/api/history', (req, res) => {
  try { res.json(JSON.parse(fs.readFileSync(HISTORY_FILE, 'utf8'))); } 
  catch(e) { res.json([]); }
});
app.get('/api/device', async (req, res) => {
  const info = await executeCommand('device-info');
  const battery = await executeCommand('battery');
  const memory = await executeCommand('memory');
  res.json({ info, battery, memory });
});
app.get('/api/gateway', (req, res) => {
  res.json(getGatewayInfo());
});
app.get('/api/connections', (req, res) => {
  res.json(Array.from(connectedDevices.values()));
});
app.post('/api/command', async (req, res) => {
  const { command } = req.body;
  const deviceInfo = {
    id: req.ip,
    ip: req.ip.replace('::ffff:', ''),
    userAgent: req.get('User-Agent')
  };
  const result = await executeCommand(command, deviceInfo);
  res.json({ success: true, result });
});
app.post('/api/ai', async (req, res) => {
  const { prompt } = req.body;
  const deviceInfo = {
    id: req.ip,
    ip: req.ip.replace('::ffff:', ''),
    userAgent: req.get('User-Agent')
  };
  const aiCommand = await aiProcessCommand(prompt);
  if (aiCommand && !aiCommand.includes('sorry') && !aiCommand.includes('cannot')) {
    const result = await executeCommand(aiCommand, deviceInfo);
    res.json({ success: true, command: aiCommand, result });
  } else {
    res.json({ success: false, message: 'Could not parse command' });
  }
});
app.post('/api/search', async (req, res) => {
  const { query } = req.body;
  const result = await webSearch(query);
  res.json({ success: true, result });
});

io.on('connection', (socket) => {
  const clientIP = socket.handshake.address.replace('::ffff:', '');
  const userAgent = socket.handshake.headers['user-agent'];
  const deviceId = `device_${++deviceCounter}_${Date.now()}`;
  
  const deviceInfo = {
    id: deviceId,
    ip: clientIP,
    userAgent: userAgent,
    connectedAt: new Date().toISOString(),
    socketId: socket.id
  };
  
  connectedDevices.set(deviceId, deviceInfo);
  saveConnectedDevices();
  
  log(`📱 Device connected from ${clientIP}`, 'system', deviceInfo);
  console.log(`📱 [${new Date().toLocaleTimeString()}] Device connected: ${clientIP}`);
  io.emit('deviceConnected', deviceInfo);
  io.emit('devicesUpdate', Array.from(connectedDevices.values()));
  
  socket.on('disconnect', () => {
    const device = connectedDevices.get(deviceId);
    if (device) {
      device.disconnectedAt = new Date().toISOString();
      log(`📱 Device disconnected from ${device.ip}`, 'system', device);
      console.log(`📱 [${new Date().toLocaleTimeString()}] Device disconnected: ${device.ip}`);
      connectedDevices.delete(deviceId);
      saveConnectedDevices();
      io.emit('deviceDisconnected', device);
      io.emit('devicesUpdate', Array.from(connectedDevices.values()));
    }
  });
  
  socket.on('getLogs', () => {
    try {
      const logs = fs.readFileSync(LOG_FILE, 'utf8').split('\n').filter(l => l).map(l => JSON.parse(l));
      socket.emit('logs', logs.slice(-100));
    } catch(e) {}
  });
  
  socket.on('command', async (cmd) => {
    const result = await executeCommand(cmd, deviceInfo);
    socket.emit('commandResult', { command: cmd, result });
  });
  
  socket.on('getGateway', () => {
    socket.emit('gatewayInfo', getGatewayInfo());
  });
});

server.listen(PORT, '0.0.0.0', () => {
  const gateway = getGatewayInfo();
  log(`🌐 Server started - Gateway: ${gateway.url}`, 'system');
  console.log(`
╔══════════════════════════════════════════════════════════════╗
║                    📱 PHONE CONTROL SYSTEM                    ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  🌐 ACCESS FROM OTHER DEVICES:                               ║
║                                                              ║
║     Gateway URL: ${gateway.url.padEnd(47)}║
║                                                              ║
║  📋 INSTRUCTIONS:                                            ║
║     1. Enable Hotspot on this phone                          ║
║     2. Connect other devices to this hotspot                 ║
║     3. Open browser and enter the Gateway URL above          ║
║     4. Control your phone remotely!                          ║
║                                                              ║
║  📊 Connection logs appear below as devices connect          ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
`);
});
EOF

mkdir -p ~/phone_server/public
cat > ~/phone_server/public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=yes">
    <title>📱 Phone Control Center</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%);
            min-height: 100vh;
            padding: 16px;
            color: #fff;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        .gateway-banner {
            background: linear-gradient(135deg, #00b4db, #0083b0);
            border-radius: 16px;
            padding: 20px;
            margin-bottom: 20px;
            text-align: center;
            box-shadow: 0 8px 32px rgba(0,0,0,0.3);
        }
        .gateway-url {
            font-size: 28px;
            font-weight: bold;
            font-family: monospace;
            background: rgba(0,0,0,0.3);
            padding: 12px 24px;
            border-radius: 12px;
            display: inline-block;
            margin: 10px 0;
            letter-spacing: 2px;
        }
        .copy-btn {
            background: rgba(255,255,255,0.2);
            border: 1px solid rgba(255,255,255,0.3);
            color: white;
            padding: 8px 16px;
            border-radius: 8px;
            cursor: pointer;
            margin-left: 10px;
        }
        h1 { 
            font-size: 24px; 
            margin-bottom: 16px;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        h2 { font-size: 18px; margin-bottom: 12px; }
        h3 { font-size: 16px; margin-bottom: 8px; color: rgba(255,255,255,0.9); }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 16px;
            margin-bottom: 16px;
        }
        .card {
            background: rgba(255,255,255,0.1);
            backdrop-filter: blur(10px);
            border-radius: 16px;
            padding: 16px;
            border: 1px solid rgba(255,255,255,0.1);
        }
        .btn-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(80px, 1fr));
            gap: 8px;
        }
        button {
            background: rgba(255,255,255,0.15);
            border: 1px solid rgba(255,255,255,0.2);
            color: white;
            padding: 10px 12px;
            border-radius: 10px;
            font-size: 13px;
            font-weight: 500;
            cursor: pointer;
            transition: all 0.2s;
            display: flex;
            flex-direction: column;
            align-items: center;
            gap: 4px;
        }
        button:hover {
            background: rgba(255,255,255,0.25);
            transform: translateY(-2px);
        }
        button:active { transform: translateY(0); }
        button svg {
            width: 24px;
            height: 24px;
            fill: currentColor;
        }
        .input-group {
            display: flex;
            gap: 8px;
            margin-top: 12px;
        }
        input, select {
            flex: 1;
            padding: 10px 12px;
            border: none;
            border-radius: 10px;
            background: rgba(255,255,255,0.15);
            color: white;
            font-size: 14px;
            border: 1px solid rgba(255,255,255,0.2);
        }
        input::placeholder { color: rgba(255,255,255,0.5); }
        .log-container {
            background: rgba(0,0,0,0.3);
            border-radius: 10px;
            padding: 12px;
            max-height: 300px;
            overflow-y: auto;
            font-family: monospace;
            font-size: 12px;
        }
        .log-entry {
            padding: 4px 0;
            border-bottom: 1px solid rgba(255,255,255,0.1);
        }
        .log-time { color: #64b5f6; }
        .log-success { color: #81c784; }
        .log-error { color: #e57373; }
        .log-system { color: #ffd54f; }
        .log-command { color: #ba68c8; }
        .devices-panel {
            background: rgba(0,0,0,0.3);
            border-radius: 10px;
            padding: 12px;
            margin-bottom: 16px;
        }
        .device-item {
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 8px;
            background: rgba(255,255,255,0.05);
            border-radius: 8px;
            margin-bottom: 4px;
        }
        .device-online {
            width: 10px;
            height: 10px;
            border-radius: 50%;
            background: #4caf50;
            animation: pulse 2s infinite;
        }
        .status-bar {
            display: flex;
            gap: 12px;
            margin-bottom: 16px;
            flex-wrap: wrap;
        }
        .status-item {
            background: rgba(255,255,255,0.1);
            backdrop-filter: blur(10px);
            padding: 8px 16px;
            border-radius: 20px;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .connection-dot {
            width: 10px;
            height: 10px;
            border-radius: 50%;
            background: #4ade80;
            animation: pulse 2s infinite;
        }
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        .ai-section {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        }
        .search-section {
            background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="gateway-banner">
            <h2 style="margin-bottom: 8px;">🌐 Gateway Access URL</h2>
            <div>
                <span class="gateway-url" id="gatewayUrl">Loading...</span>
                <button class="copy-btn" onclick="copyGatewayUrl()">📋 Copy</button>
            </div>
            <p style="margin-top: 12px; opacity: 0.9;">Connect other devices to this hotspot and open this URL</p>
        </div>

        <div class="devices-panel">
            <h3>📱 Connected Devices <span id="deviceCount">(0)</span></h3>
            <div id="devicesList">
                <div class="device-item" style="justify-content: center; opacity: 0.7;">No devices connected</div>
            </div>
        </div>

        <h1>
            <svg width="32" height="32" viewBox="0 0 24 24" fill="currentColor">
                <path d="M17 1.01L7 1c-1.1 0-2 .9-2 2v18c0 1.1.9 2 2 2h10c1.1 0 2-.9 2-2V3c0-1.1-.9-1.99-2-1.99zM17 19H7V5h10v14z"/>
            </svg>
            Remote Phone Control Center
        </h1>
        
        <div class="status-bar" id="statusBar">
            <div class="status-item"><span class="connection-dot"></span><span id="connectionStatus">Connected</span></div>
            <div class="status-item"><span id="deviceModel">Loading...</span></div>
            <div class="status-item"><span id="batteryLevel">🔋 --%</span></div>
        </div>

        <div class="grid">
            <div class="card ai-section">
                <h2>🤖 AI Assistant</h2>
                <p style="margin-bottom: 12px; opacity: 0.9;">Tell me what to do on your phone...</p>
                <div class="input-group">
                    <input type="text" id="aiInput" placeholder="e.g., open chrome and search for cats">
                    <button onclick="sendAICommand()" style="min-width: 80px;">Send</button>
                </div>
                <div id="aiResult" style="margin-top: 12px; font-size: 14px;"></div>
            </div>

            <div class="card search-section">
                <h2>🔍 Web Search</h2>
                <div class="input-group">
                    <input type="text" id="searchInput" placeholder="Search the web...">
                    <button onclick="webSearch()">Search</button>
                </div>
                <div id="searchResult" style="margin-top: 12px; max-height: 150px; overflow-y: auto; font-size: 13px;"></div>
            </div>
        </div>

        <div class="grid">
            <div class="card">
                <h2>📱 Navigation</h2>
                <div class="btn-grid">
                    <button onclick="sendCommand('home')"><svg viewBox="0 0 24 24"><path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"/></svg>Home</button>
                    <button onclick="sendCommand('back')"><svg viewBox="0 0 24 24"><path d="M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z"/></svg>Back</button>
                    <button onclick="sendCommand('recent')"><svg viewBox="0 0 24 24"><path d="M4 8h4V4H4v4zm6 12h4v-4h-4v4zm-6 0h4v-4H4v4zm0-6h4v-4H4v4zm6 0h4v-4h-4v4zm6-10v4h4V4h-4zm-6 4h4V4h-4v4zm6 6h4v-4h-4v4zm0 6h4v-4h-4v4z"/></svg>Recent</button>
                    <button onclick="sendCommand('menu')"><svg viewBox="0 0 24 24"><path d="M3 18h18v-2H3v2zm0-5h18v-2H3v2zm0-7v2h18V6H3z"/></svg>Menu</button>
                </div>
            </div>

            <div class="card">
                <h2>🔊 Media</h2>
                <div class="btn-grid">
                    <button onclick="sendCommand('volume-up')"><svg viewBox="0 0 24 24"><path d="M3 9v6h4l5 5V4L7 9H3z"/></svg>Vol+</button>
                    <button onclick="sendCommand('volume-down')"><svg viewBox="0 0 24 24"><path d="M18.5 12c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02z"/></svg>Vol-</button>
                    <button onclick="sendCommand('mute')"><svg viewBox="0 0 24 24"><path d="M16.5 12c0-1.77-1.02-3.29-2.5-4.03v2.21l2.45 2.45c.03-.2.05-.41.05-.63z"/></svg>Mute</button>
                    <button onclick="sendCommand('play-pause')"><svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>Play</button>
                    <button onclick="sendCommand('next')"><svg viewBox="0 0 24 24"><path d="M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z"/></svg>Next</button>
                    <button onclick="sendCommand('previous')"><svg viewBox="0 0 24 24"><path d="M6 6h2v12H6zm3.5 6l8.5 6V6z"/></svg>Prev</button>
                </div>
            </div>
        </div>

        <div class="grid">
            <div class="card">
                <h2>⚡ Power & Display</h2>
                <div class="btn-grid">
                    <button onclick="sendCommand('power')"><svg viewBox="0 0 24 24"><path d="M13 3h-2v10h2V3zm4.83 2.17l-1.42 1.42C17.99 7.86 19 9.81 19 12c0 3.87-3.13 7-7 7s-7-3.13-7-7c0-2.19 1.01-4.14 2.59-5.42L6.17 5.17C4.23 6.82 3 9.26 3 12c0 4.97 4.03 9 9 9s9-4.03 9-9c0-2.74-1.23-5.18-3.17-6.83z"/></svg>Power</button>
                    <button onclick="sendCommand('screen-on')"><svg viewBox="0 0 24 24"><path d="M12 7V3H2v18h20V7H12zM6 19H4v-2h2v2zm0-4H4v-2h2v2zm0-4H4V9h2v2zm0-4H4V5h2v2zm4 12H8v-2h2v2zm0-4H8v-2h2v2zm0-4H8V9h2v2zm0-4H8V5h2v2zm10 12h-8v-2h2v-2h-2v-2h2v-2h-2V9h8v10z"/></svg>Screen On</button>
                    <button onclick="sendCommand('screen-off')"><svg viewBox="0 0 24 24"><path d="M20 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2z"/></svg>Screen Off</button>
                    <button onclick="sendCommand('lock')"><svg viewBox="0 0 24 24"><path d="M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2zm-6 9c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2z"/></svg>Lock</button>
                    <button onclick="sendCommand('sleep')"><svg viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z"/></svg>Sleep</button>
                    <button onclick="sendCommand('wake')"><svg viewBox="0 0 24 24"><path d="M20 12c0-4.41-3.59-8-8-8s-8 3.59-8 8 3.59 8 8 8 8-3.59 8-8z"/></svg>Wake</button>
                </div>
            </div>

            <div class="card">
                <h2>📶 Connectivity</h2>
                <div class="btn-grid">
                    <button onclick="sendCommand('wifi on')"><svg viewBox="0 0 24 24"><path d="M1 9l2 2c4.97-4.97 13.03-4.97 18 0l2-2C16.44 3.9 7.56 3.9 1 9z"/></svg>WiFi On</button>
                    <button onclick="sendCommand('wifi off')"><svg viewBox="0 0 24 24"><path d="M1 9l2 2c4.97-4.97 13.03-4.97 18 0l2-2C16.44 3.9 7.56 3.9 1 9z"/></svg>WiFi Off</button>
                    <button onclick="sendCommand('hotspot on')"><svg viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z"/></svg>Hotspot On</button>
                    <button onclick="sendCommand('hotspot off')"><svg viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z"/></svg>Hotspot Off</button>
                    <button onclick="sendCommand('bluetooth on')"><svg viewBox="0 0 24 24"><path d="M17.71 7.71L12 2h-1v7.59L6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 11 14.41V22h1l5.71-5.71-4.3-4.29 4.3-4.29z"/></svg>BT On</button>
                    <button onclick="sendCommand('bluetooth off')"><svg viewBox="0 0 24 24"><path d="M17.71 7.71L12 2h-1v7.59L6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 11 14.41V22h1l5.71-5.71-4.3-4.29 4.3-4.29z"/></svg>BT Off</button>
                </div>
            </div>
        </div>

        <div class="grid">
            <div class="card">
                <h2>🎯 Touch Control</h2>
                <div class="input-group">
                    <input type="number" id="tapX" placeholder="X" value="500">
                    <input type="number" id="tapY" placeholder="Y" value="500">
                    <button onclick="sendCommand('tap ' + document.getElementById('tapX').value + ' ' + document.getElementById('tapY').value)">Tap</button>
                </div>
                <div class="input-group">
                    <input type="number" id="swipeX1" placeholder="X1" value="500">
                    <input type="number" id="swipeY1" placeholder="Y1" value="1500">
                    <input type="number" id="swipeX2" placeholder="X2" value="500">
                    <input type="number" id="swipeY2" placeholder="Y2" value="500">
                    <button onclick="sendCommand('swipe ' + document.getElementById('swipeX1').value + ' ' + document.getElementById('swipeY1').value + ' ' + document.getElementById('swipeX2').value + ' ' + document.getElementById('swipeY2').value)">Swipe</button>
                </div>
                <div class="input-group">
                    <input type="text" id="textInput" placeholder="Type text...">
                    <button onclick="sendCommand('text ' + document.getElementById('textInput').value)">Type</button>
                </div>
            </div>

            <div class="card">
                <h2>📊 Quick Actions</h2>
                <div class="btn-grid">
                    <button onclick="sendCommand('notification')"><svg viewBox="0 0 24 24"><path d="M12 22c1.1 0 2-.9 2-2h-4c0 1.1.9 2 2 2zm6-6v-5c0-3.07-1.63-5.64-4.5-6.32V4c0-.83-.67-1.5-1.5-1.5s-1.5.67-1.5 1.5v.68C7.64 5.36 6 7.92 6 11v5l-2 2v1h16v-1l-2-2z"/></svg>Notifications</button>
                    <button onclick="sendCommand('quick-settings')"><svg viewBox="0 0 24 24"><path d="M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58c.18-.14.23-.41.12-.61l-1.92-3.32c-.12-.22-.37-.29-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54c-.04-.24-.24-.41-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.09.63-.09.94 0 .31.02.64.07.94l-2.03 1.58c-.18.14-.23.41-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58z"/></svg>Quick Settings</button>
                    <button onclick="sendCommand('camera')"><svg viewBox="0 0 24 24"><path d="M9 3L7.17 5H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2h-3.17L15 3H9z"/></svg>Camera</button>
                    <button onclick="sendCommand('ui-dump')"><svg viewBox="0 0 24 24"><path d="M21 3H3c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h18c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2z"/></svg>UI Dump</button>
                    <button onclick="sendCommand('screenshot')"><svg viewBox="0 0 24 24"><path d="M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2z"/></svg>Screenshot</button>
                </div>
            </div>
        </div>

        <div class="card">
            <h2>📝 Command Log & History</h2>
            <div class="input-group">
                <input type="text" id="customCommand" placeholder="Enter any command...">
                <button onclick="sendCommand(document.getElementById('customCommand').value)">Execute</button>
                <button onclick="clearLogs()">Clear</button>
            </div>
            <div class="log-container" id="logContainer"></div>
        </div>
    </div>

    <script src="/socket.io/socket.io.js"></script>
    <script>
        const socket = io();
        const logContainer = document.getElementById('logContainer');
        
        socket.on('connect', () => {
            document.getElementById('connectionStatus').textContent = 'Connected';
            socket.emit('getLogs');
            socket.emit('getGateway');
            loadDeviceInfo();
            loadGatewayInfo();
        });
        
        socket.on('disconnect', () => {
            document.getElementById('connectionStatus').textContent = 'Disconnected';
        });
        
        socket.on('log', (log) => {
            addLogEntry(log);
        });
        
        socket.on('logs', (logs) => {
            logContainer.innerHTML = '';
            logs.reverse().forEach(log => addLogEntry(log));
        });
        
        socket.on('commandResult', (data) => {
            addLogEntry({
                timestamp: new Date().toISOString(),
                type: 'success',
                message: `${data.command}: ${data.result}`
            });
        });
        
        socket.on('gatewayInfo', (info) => {
            document.getElementById('gatewayUrl').textContent = info.url;
        });
        
        socket.on('deviceConnected', (device) => {
            addLogEntry({
                timestamp: new Date().toISOString(),
                type: 'system',
                message: `📱 Device connected: ${device.ip}`
            });
        });
        
        socket.on('deviceDisconnected', (device) => {
            addLogEntry({
                timestamp: new Date().toISOString(),
                type: 'system',
                message: `📱 Device disconnected: ${device.ip}`
            });
        });
        
        socket.on('devicesUpdate', (devices) => {
            updateDevicesList(devices);
        });
        
        function addLogEntry(log) {
            const div = document.createElement('div');
            div.className = 'log-entry';
            const time = new Date(log.timestamp).toLocaleTimeString();
            const typeClass = `log-${log.type}`;
            const deviceTag = log.device ? `[${log.device.ip}] ` : '';
            div.innerHTML = `<span class="log-time">[${time}]</span> <span class="${typeClass}">${deviceTag}${log.message}</span>`;
            logContainer.appendChild(div);
            logContainer.scrollTop = logContainer.scrollHeight;
        }
        
        function updateDevicesList(devices) {
            const list = document.getElementById('devicesList');
            const count = document.getElementById('deviceCount');
            count.textContent = `(${devices.length})`;
            
            if (devices.length === 0) {
                list.innerHTML = '<div class="device-item" style="justify-content: center; opacity: 0.7;">No devices connected</div>';
                return;
            }
            
            list.innerHTML = devices.map(d => `
                <div class="device-item">
                    <span class="device-online"></span>
                    <span style="flex:1;">${d.ip}</span>
                    <span style="font-size:12px; opacity:0.7;">${d.userAgent ? d.userAgent.split(' ').slice(-2).join(' ') : 'Unknown'}</span>
                    <span style="font-size:11px; opacity:0.5;">${new Date(d.connectedAt).toLocaleTimeString()}</span>
                </div>
            `).join('');
        }
        
        function sendCommand(cmd) {
            socket.emit('command', cmd);
        }
        
        function clearLogs() {
            logContainer.innerHTML = '';
        }
        
        async function loadGatewayInfo() {
            try {
                const res = await fetch('/api/gateway');
                const data = await res.json();
                document.getElementById('gatewayUrl').textContent = data.url;
            } catch(e) {}
        }
        
        async function loadDeviceInfo() {
            try {
                const res = await fetch('/api/device');
                const data = await res.json();
                const info = data.info.split('\n');
                document.getElementById('deviceModel').textContent = `${info[2] || 'Android'} ${info[1] || ''}`;
                const batteryMatch = data.battery.match(/level: (\d+)/);
                if (batteryMatch) {
                    document.getElementById('batteryLevel').textContent = `🔋 ${batteryMatch[1]}%`;
                }
            } catch(e) {}
        }
        
        function copyGatewayUrl() {
            const url = document.getElementById('gatewayUrl').textContent;
            navigator.clipboard.writeText(url).then(() => {
                alert('Gateway URL copied to clipboard!');
            });
        }
        
        async function sendAICommand() {
            const input = document.getElementById('aiInput');
            const prompt = input.value.trim();
            if (!prompt) return;
            
            addLogEntry({ timestamp: new Date().toISOString(), type: 'system', message: `AI Request: ${prompt}` });
            try {
                const res = await fetch('/api/ai', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ prompt })
                });
                const data = await res.json();
                if (data.success) {
                    document.getElementById('aiResult').innerHTML = `✅ Executed: ${data.command}<br>📱 ${data.result}`;
                } else {
                    document.getElementById('aiResult').innerHTML = `❌ ${data.message}`;
                }
            } catch(e) {
                document.getElementById('aiResult').innerHTML = '❌ AI service error';
            }
            input.value = '';
        }
        
        async function webSearch() {
            const input = document.getElementById('searchInput');
            const query = input.value.trim();
            if (!query) return;
            
            addLogEntry({ timestamp: new Date().toISOString(), type: 'system', message: `Search: ${query}` });
            try {
                const res = await fetch('/api/search', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ query })
                });
                const data = await res.json();
                document.getElementById('searchResult').innerHTML = data.result;
            } catch(e) {
                document.getElementById('searchResult').innerHTML = 'Search failed';
            }
            input.value = '';
        }
        
        async function loadConnections() {
            try {
                const res = await fetch('/api/connections');
                const devices = await res.json();
                updateDevicesList(devices);
            } catch(e) {}
        }
        
        setInterval(loadDeviceInfo, 30000);
        setInterval(loadConnections, 5000);
        loadDeviceInfo();
        loadConnections();
        loadGatewayInfo();
    </script>
</body>
</html>
EOF

cd ~/phone_server
npm init -y > /dev/null 2>&1
npm install express socket.io > /dev/null 2>&1

echo ""
echo "📝 Step 6/7: Creating connection log viewer..."
cat > ~/view_connections.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
echo "📱 Connected Devices Log"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -f ~/connected_devices.json ]; then
    cat ~/connected_devices.json | node -e "
        const data = JSON.parse(require('fs').readFileSync(0, 'utf8'));
        if (data.length === 0) {
            console.log('No devices connected yet');
        } else {
            data.forEach((d, i) => {
                console.log(\`\${i+1}. IP: \${d.ip}\`);
                console.log(\`   Connected: \${new Date(d.connectedAt).toLocaleString()}\`);
                if (d.disconnectedAt) console.log(\`   Disconnected: \${new Date(d.disconnectedAt).toLocaleString()}\`);
                console.log(\`   Device: \${d.userAgent ? d.userAgent.split(' ').slice(-2).join(' ') : 'Unknown'}\`);
                console.log('');
            });
        }
    "
else
    echo "No connection history yet"
fi
echo ""
echo "📋 Live Termux Log:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
tail -f ~/phone_control.log | grep --line-buffered "Device" | while read line; do
    echo "$line" | node -e "
        try {
            const log = JSON.parse(require('fs').readFileSync(0, 'utf8'));
            if (log.message.includes('Device')) {
                const time = new Date(log.timestamp).toLocaleTimeString();
                console.log(\`[\${time}] \${log.message}\`);
            }
        } catch(e) {}
    "
done
EOF
chmod +x ~/view_connections.sh

echo "✅ Connection log viewer created"

echo ""
echo "🎉 Step 7/7: Starting server..."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ INSTALLATION COMPLETE!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📱 To view connected devices in Termux:"
echo "   bash ~/view_connections.sh"
echo ""

node ~/phone_server/server.js
