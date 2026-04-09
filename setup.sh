#!/data/data/com.termux/files/usr/bin/bash

export DEBIAN_FRONTEND=noninteractive
export DPKG_FORCE=confold
export LANG=C
export LC_ALL=C
export NODE_OPTIONS=--dns-result-order=ipv4first

clear
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "                    🔥 PHONE GATEWAY CONTROLLER v2.0 🔥"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

pkill -f "node.*gateway" 2>/dev/null
pkill -f "http-server" 2>/dev/null

echo "[1/7] Installing dependencies..."
pkg update -y -o Dpkg::Options::="--force-confold" >/dev/null 2>&1
pkg install -y nodejs git nmap curl jq termux-api openssl-tool netcat-openbsd >/dev/null 2>&1

echo "[2/7] Setting up project..."
mkdir -p ~/phonegate/{data,logs,web,tools,keys,uploads,temp}
cd ~/phonegate

npm init -y >/dev/null 2>&1
npm install express socket.io multer bcryptjs express-rate-limit helmet compression sqlite3 better-sqlite3 axios open ws >/dev/null 2>&1

echo "[3/7] Configuring Shizuku..."
termux-setup-storage <<< "y" >/dev/null 2>&1
sleep 2

SHIZUKU_DIR="$HOME/storage/shared/Shizuku"
mkdir -p "$SHIZUKU_DIR"

cat > "$SHIZUKU_DIR/copy.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
BASEDIR=$(dirname "${0}")
BIN=/data/data/com.termux/files/usr/bin
HOME=/data/data/com.termux/files/home
DEX="${BASEDIR}/rish_shizuku.dex"
[ ! -f "${DEX}" ] && exit 1
ARCH=$(getprop ro.product.cpu.abi 2>/dev/null || echo "arm64-v8a")
case "$ARCH" in
  arm64*) LIB_ARCH="arm64" ;;
  armeabi*) LIB_ARCH="arm" ;;
  x86_64*) LIB_ARCH="x86_64" ;;
  x86*) LIB_ARCH="x86" ;;
  *) LIB_ARCH="arm64" ;;
esac
cat > "${BIN}/shizuku" << EEF
#!/data/data/com.termux/files/usr/bin/bash
ports=\$(nmap -sT -p30000-50000 --open localhost 2>/dev/null | grep "open" | cut -f1 -d/)
for port in \${ports}; do
  result=\$(adb connect "localhost:\${port}" 2>/dev/null)
  if [[ "\$result" =~ "connected" || "\$result" =~ "already" ]]; then
    adb shell "\$(adb shell pm path moe.shizuku.privileged.api | sed 's/^package://;s/base\\\\.apk/lib\\\\/${LIB_ARCH}\\\\/libshizuku\\\\.so/')"
    adb shell settings put global adb_wifi_enabled 0
    exit 0
  fi
done
exit 1
EEF
cat > "${BIN}/rish" << EEF
#!/data/data/com.termux/files/usr/bin/bash
[ -z "\$RISH_APPLICATION_ID" ] && export RISH_APPLICATION_ID="com.termux"
/system/bin/app_process -Djava.class.path="${HOME}/rish_shizuku.dex" /system/bin --nice-name=rish rikka.shizuku.shell.ShizukuShellLoader "\${@}"
EEF
chmod +x "${BIN}/shizuku" "${BIN}/rish"
cp -f "${DEX}" "${HOME}/rish_shizuku.dex"
chmod -w "${HOME}/rish_shizuku.dex"
EOF

chmod +x "$SHIZUKU_DIR/copy.sh"
bash "$SHIZUKU_DIR/copy.sh" 2>/dev/null

echo "[4/7] Creating phone controller..."
cat > ~/phonegate/phone_control.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
execute() {
  if command -v rish &>/dev/null; then
    rish -c "$@" 2>&1
  elif command -v adb &>/dev/null && adb get-state 1>/dev/null 2>&1; then
    adb shell "$@" 2>&1
  else
    echo "ERROR: No device connection"
    return 1
  fi
}
case "$1" in
  tap) execute "input tap $2 $3" ;;
  longtap) execute "input swipe $2 $3 $2 $3 1000" ;;
  doubletap) execute "input tap $2 $3 && sleep 0.1 && input tap $2 $3" ;;
  swipe) execute "input swipe $2 $3 $4 $5 ${6:-500}" ;;
  scrollup) execute "input swipe 500 1500 500 500" ;;
  scrolldown) execute "input swipe 500 500 500 1500" ;;
  scrollleft) execute "input swipe 900 1000 100 1000" ;;
  scrollright) execute "input swipe 100 1000 900 1000" ;;
  text) execute "input text '$2'" ;;
  key) execute "input keyevent $2" ;;
  home) execute "input keyevent 3" ;;
  back) execute "input keyevent 4" ;;
  recent) execute "input keyevent 187" ;;
  power) execute "input keyevent 26" ;;
  volume_up) execute "input keyevent 24" ;;
  volume_down) execute "input keyevent 25" ;;
  mute) execute "input keyevent 164" ;;
  playpause) execute "input keyevent 85" ;;
  next) execute "input keyevent 87" ;;
  prev) execute "input keyevent 88" ;;
  screenshot) execute "screencap -p ${2:-/sdcard/screenshot.png}" ;;
  open_app) execute "monkey -p $2 -c android.intent.category.LAUNCHER 1" ;;
  open_url) execute "am start -a android.intent.action.VIEW -d '$2'" ;;
  youtube) execute "am start -a android.intent.action.VIEW -d 'https://www.youtube.com/results?search_query=${2// /+}'" ;;
  google) execute "am start -a android.intent.action.VIEW -d 'https://www.google.com/search?q=${2// /+}'" ;;
  maps) execute "am start -a android.intent.action.VIEW -d 'geo:0,0?q=${2// /+}'" ;;
  call) execute "am start -a android.intent.action.CALL -d tel:$2" ;;
  sms) execute "am start -a android.intent.action.SENDTO -d sms:$2 --es sms_body '$3'" ;;
  battery) execute "dumpsys battery" | grep -E "level|temperature|voltage|status" ;;
  wifi_on) execute "svc wifi enable" ;;
  wifi_off) execute "svc wifi disable" ;;
  bluetooth_on) execute "service call bluetooth_manager 6" ;;
  bluetooth_off) execute "service call bluetooth_manager 8" ;;
  airplane_on) execute "settings put global airplane_mode_on 1 && am broadcast -a android.intent.action.AIRPLANE_MODE" ;;
  airplane_off) execute "settings put global airplane_mode_on 0 && am broadcast -a android.intent.action.AIRPLANE_MODE" ;;
  brightness) execute "settings put system screen_brightness $2" ;;
  brightness_auto) execute "settings put system screen_brightness_mode $2" ;;
  volume) execute "media volume --set $2" ;;
  ringermode) execute "cmd audio set-ringer-mode $2" ;;
  clipboard_get) execute "cmd clipboard get" ;;
  clipboard_set) execute "cmd clipboard set '$2'" ;;
  notify) execute "cmd notification post -S bigtext -t '$2' 'phonegate' '$3'" ;;
  toast) execute "am broadcast -a com.termux.toast --es message '$2'" ;;
  vibrate) execute "cmd vibrator vibrate $2" ;;
  flashlight_on) execute "cmd flashlight enable" ;;
  flashlight_off) execute "cmd flashlight disable" ;;
  location_on) execute "settings put secure location_mode 3" ;;
  location_off) execute "settings put secure location_mode 0" ;;
  rotatescreen) execute "settings put system accelerometer_rotation $2" ;;
  lockscreen) execute "input keyevent 26 && input keyevent 26" ;;
  screenon) execute "input keyevent 224" ;;
  screenoff) execute "input keyevent 223" ;;
  sleep) execute "input keyevent 26" ;;
  wake) execute "input keyevent 26" ;;
  ui_dump) execute "uiautomator dump /sdcard/ui.xml" >/dev/null 2>&1 && execute "cat /sdcard/ui.xml" | grep -oP '(text|content-desc)="[^"]*"[^>]*bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | while read line; do bounds=$(echo "$line" | grep -oP '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]'); text=$(echo "$line" | grep -oP '(?<=text=")[^"]*|(?<=content-desc=")[^"]*' | head -1); [ -n "$text" ] && echo "$bounds|$text"; done ;;
  ui_click) execute "uiautomator dump /sdcard/ui.xml" >/dev/null 2>&1 && execute "cat /sdcard/ui.xml" | grep -oP "(?<=text=\"$2\"|content-desc=\"$2\")[^>]*bounds=\"\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]\"" | grep -oP '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]' | head -1 | while read bounds; do x1=$(echo $bounds | grep -oP '(?<=\[)[0-9]+(?=,)'); y1=$(echo $bounds | grep -oP '(?<=,)[0-9]+(?=\])'); x2=$(echo $bounds | grep -oP '(?<=\]\[)[0-9]+(?=,)'); y2=$(echo $bounds | grep -oP '(?<=,)[0-9]+(?=\]$)'); cx=$(((x1+x2)/2)); cy=$(((y1+y2)/2)); execute "input tap $cx $cy"; done ;;
  app_list) execute "pm list packages" | sed 's/package://g' ;;
  app_info) execute "dumpsys package $2 | grep -E 'versionName|versionCode|firstInstallTime'" ;;
  app_force_stop) execute "am force-stop $2" ;;
  app_clear_data) execute "pm clear $2" ;;
  app_uninstall) execute "pm uninstall $2" ;;
  device_info) execute "getprop ro.product.model && getprop ro.build.version.release && getprop ro.product.manufacturer" ;;
  storage_info) execute "df -h /sdcard" ;;
  ram_info) execute "cat /proc/meminfo | grep -E 'MemTotal|MemFree|MemAvailable'" ;;
  cpu_info) execute "cat /proc/cpuinfo | grep -E 'processor|Hardware'" ;;
  network_info) execute "dumpsys connectivity | grep -E 'NetworkAgentInfo|state'" ;;
  ip_info) execute "ifconfig wlan0 | grep 'inet addr'" ;;
  hotspot_on) execute "svc wifi disable && cmd wifi set-wifi-enabled disabled && cmd connectivity tethering start" ;;
  hotspot_off) execute "cmd connectivity tethering stop" ;;
  reboot) execute "reboot" ;;
  reboot_recovery) execute "reboot recovery" ;;
  reboot_bootloader) execute "reboot bootloader" ;;
  poweroff) execute "reboot -p" ;;
  shell) execute "$2" ;;
  troll_screen_flip) execute "settings put global window_animation_scale 10 && settings put global transition_animation_scale 10" ;;
  troll_screen_normal) execute "settings put global window_animation_scale 1 && settings put global transition_animation_scale 1" ;;
  troll_invert_colors) execute "settings put secure accessibility_display_inversion_enabled $2" ;;
  troll_font_huge) execute "settings put system font_scale 2.0" ;;
  troll_font_normal) execute "settings put system font_scale 1.0" ;;
  troll_spam_notify) for i in {1..10}; do execute "cmd notification post -S bigtext -t 'SPAM $i' 'troll' 'BOO!'"; done ;;
  troll_vibrate_crazy) execute "cmd vibrator vibrate 1000" ;;
  troll_open_random) execute "monkey -p $(pm list packages | shuf -n 1 | sed 's/package://g') -c android.intent.category.LAUNCHER 1" ;;
  troll_rotate) execute "settings put system user_rotation $(($2 % 4))" ;;
  troll_rotate_off) execute "settings put system user_rotation 0" ;;
  troll_volume_max) execute "media volume --set 15" ;;
  troll_brightness_flash) for i in {1..5}; do execute "settings put system screen_brightness 255"; sleep 0.2; execute "settings put system screen_brightness 10"; sleep 0.2; done ;;
  *) echo "Unknown command: $1" ;;
esac
EOF

chmod +x ~/phonegate/phone_control.sh

echo "[5/7] Creating gateway server..."
cat > ~/phonegate/gateway.js << 'EOF'
const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');
const axios = require('axios');
const Database = require('better-sqlite3');
const bcrypt = require('bcryptjs');
const multer = require('multer');
const crypto = require('crypto');

const app = express();
const server = http.createServer(app);
const io = socketIo(server);
const upload = multer({ dest: path.join(__dirname, 'uploads') });

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, 'web')));

const db = new Database(path.join(__dirname, 'data', 'gateway.db'));
db.exec(`
  CREATE TABLE IF NOT EXISTS access_keys (key TEXT PRIMARY KEY, created_at DATETIME DEFAULT CURRENT_TIMESTAMP, last_used DATETIME);
  CREATE TABLE IF NOT EXISTS messages (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT, role TEXT, content TEXT, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP);
  CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT);
  CREATE TABLE IF NOT EXISTS command_history (id INTEGER PRIMARY KEY AUTOINCREMENT, command TEXT, result TEXT, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP);
`);

const settings = {
  get: (key, def = '') => { const row = db.prepare('SELECT value FROM settings WHERE key = ?').get(key); return row ? row.value : def; },
  set: (key, value) => { db.prepare('INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)').run(key, value); }
};

if (!settings.get('access_key')) {
  const newKey = crypto.randomBytes(16).toString('hex');
  settings.set('access_key', newKey);
  console.log('\n🔥 ACCESS KEY: ' + newKey + ' 🔥\n');
}

const ACCESS_KEY = settings.get('access_key');
const PORT = settings.get('port', '3000');

const authenticate = (req, res, next) => {
  const key = req.headers['x-access-key'] || req.query.key;
  if (key === ACCESS_KEY) {
    db.prepare('UPDATE access_keys SET last_used = CURRENT_TIMESTAMP WHERE key = ?').run(key);
    next();
  } else {
    res.status(401).json({ error: 'Invalid access key' });
  }
};

async function aiResponse(prompt, context = []) {
  try {
    const messages = [
      { role: 'system', content: 'You are PhoneGateway AI, controlling an Android device. You can execute commands via the system. Be helpful and direct. Available commands: tap, swipe, text, open_app, ui_dump, screenshot, battery, wifi_on/off, bluetooth_on/off, volume, brightness, location_on/off, flashlight_on/off, call, sms, open_url, youtube, google, and 50+ more. Respond naturally and suggest commands when appropriate.' },
      ...context,
      { role: 'user', content: prompt }
    ];
    const response = await axios.post('https://text.pollinations.ai/', { messages, model: 'openai', seed: Math.floor(Math.random() * 1000000) }, { timeout: 30000 });
    return response.data;
  } catch (error) {
    try {
      const fallback = await axios.get(`https://text.pollinations.ai/${encodeURIComponent(prompt)}`);
      return fallback.data;
    } catch {
      return null;
    }
  }
}

async function webSearch(query) {
  try {
    const response = await axios.get(`https://api.duckduckgo.com/?q=${encodeURIComponent(query)}&format=json&no_html=1&skip_disambig=1`);
    if (response.data.Abstract) return response.data.Abstract;
    if (response.data.RelatedTopics?.[0]?.Text) return response.data.RelatedTopics[0].Text;
    return null;
  } catch {
    return null;
  }
}

function executeCommand(command) {
  return new Promise((resolve) => {
    exec(command, { timeout: 15000 }, (error, stdout, stderr) => {
      const result = error ? `Error: ${error.message}` : (stdout || stderr || 'Command executed');
      db.prepare('INSERT INTO command_history (command, result) VALUES (?, ?)').run(command, result);
      resolve(result);
    });
  });
}

app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'web', 'index.html'));
});

app.get('/api/status', authenticate, async (req, res) => {
  const battery = await executeCommand('~/phonegate/phone_control.sh battery');
  const device = await executeCommand('~/phonegate/phone_control.sh device_info');
  res.json({ 
    status: 'online', 
    battery: battery.split('\n')[0],
    device: device.split('\n')[0],
    access_key: ACCESS_KEY,
    port: PORT
  });
});

app.post('/api/command', authenticate, async (req, res) => {
  const { command, args } = req.body;
  let fullCmd = `~/phonegate/phone_control.sh ${command}`;
  if (args) fullCmd += ` ${args}`;
  const result = await executeCommand(fullCmd);
  res.json({ success: true, result });
});

app.post('/api/ai', authenticate, async (req, res) => {
  const { prompt, session_id } = req.body;
  const context = session_id ? db.prepare('SELECT role, content FROM messages WHERE session_id = ? ORDER BY timestamp DESC LIMIT 10').all(session_id) : [];
  const response = await aiResponse(prompt, context);
  if (session_id) {
    db.prepare('INSERT INTO messages (session_id, role, content) VALUES (?, ?, ?)').run(session_id, 'user', prompt);
    db.prepare('INSERT INTO messages (session_id, role, content) VALUES (?, ?, ?)').run(session_id, 'assistant', response);
  }
  res.json({ response });
});

app.post('/api/search', authenticate, async (req, res) => {
  const { query } = req.body;
  const result = await webSearch(query);
  res.json({ result });
});

app.get('/api/commands', authenticate, (req, res) => {
  const commands = [
    'tap [x] [y]', 'longtap [x] [y]', 'doubletap [x] [y]', 'swipe [x1] [y1] [x2] [y2]',
    'scrollup', 'scrolldown', 'scrollleft', 'scrollright', 'text [content]', 'key [code]',
    'home', 'back', 'recent', 'power', 'volume_up', 'volume_down', 'mute', 'playpause', 'next', 'prev',
    'screenshot', 'open_app [package]', 'open_url [url]', 'youtube [query]', 'google [query]',
    'maps [location]', 'call [number]', 'sms [number] [message]', 'battery', 'wifi_on', 'wifi_off',
    'bluetooth_on', 'bluetooth_off', 'airplane_on', 'airplane_off', 'brightness [0-255]',
    'brightness_auto [0|1]', 'volume [0-15]', 'ringermode [0|1|2]', 'clipboard_get', 'clipboard_set [text]',
    'notify [title] [message]', 'toast [message]', 'vibrate [ms]', 'flashlight_on', 'flashlight_off',
    'location_on', 'location_off', 'rotatescreen [0|1]', 'lockscreen', 'screenon', 'screenoff',
    'ui_dump', 'ui_click [text]', 'app_list', 'app_info [package]', 'app_force_stop [package]',
    'app_clear_data [package]', 'app_uninstall [package]', 'device_info', 'storage_info', 'ram_info',
    'cpu_info', 'network_info', 'ip_info', 'hotspot_on', 'hotspot_off', 'reboot', 'poweroff',
    'shell [command]', 'troll_screen_flip', 'troll_screen_normal', 'troll_invert_colors [0|1]',
    'troll_font_huge', 'troll_font_normal', 'troll_spam_notify', 'troll_vibrate_crazy',
    'troll_open_random', 'troll_rotate [0-3]', 'troll_volume_max', 'troll_brightness_flash'
  ];
  res.json({ commands });
});

app.get('/api/history', authenticate, (req, res) => {
  const history = db.prepare('SELECT * FROM command_history ORDER BY timestamp DESC LIMIT 100').all();
  res.json({ history });
});

app.post('/api/upload', authenticate, upload.single('file'), (req, res) => {
  res.json({ success: true, file: req.file });
});

io.use((socket, next) => {
  const key = socket.handshake.auth.key || socket.handshake.query.key;
  if (key === ACCESS_KEY) next();
  else next(new Error('Invalid access key'));
});

io.on('connection', (socket) => {
  console.log('Client connected');
  socket.on('command', async (data) => {
    const result = await executeCommand(`~/phonegate/phone_control.sh ${data.command} ${data.args || ''}`);
    socket.emit('result', { command: data.command, result });
  });
  socket.on('ai', async (data) => {
    const response = await aiResponse(data.prompt);
    socket.emit('ai_response', { response });
  });
  socket.on('disconnect', () => console.log('Client disconnected'));
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`\n🌐 Gateway running on port ${PORT}`);
  console.log(`🔑 Access key: ${ACCESS_KEY}`);
  console.log(`📱 Connect via: http://$(ip route get 1 | grep -oP 'src \K\S+'):${PORT}\n`);
});
EOF

echo "[6/7] Creating web interface..."
cat > ~/phonegate/web/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Phone Gateway Controller</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', system-ui, sans-serif; background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%); min-height: 100vh; color: #eee; }
        .container { max-width: 1400px; margin: 0 auto; padding: 20px; }
        .header { text-align: center; padding: 30px 0; border-bottom: 2px solid #0f3460; margin-bottom: 30px; }
        .header h1 { font-size: 2.5em; background: linear-gradient(45deg, #e94560, #533483); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
        .status-bar { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .status-card { background: #0f3460; padding: 20px; border-radius: 15px; text-align: center; box-shadow: 0 10px 30px rgba(0,0,0,0.3); }
        .status-card h3 { color: #e94560; margin-bottom: 10px; }
        .main-panel { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
        .panel { background: #0f3460; border-radius: 15px; padding: 20px; box-shadow: 0 10px 30px rgba(0,0,0,0.3); }
        .panel h2 { color: #e94560; margin-bottom: 20px; border-bottom: 1px solid #533483; padding-bottom: 10px; }
        .chat-container { height: 400px; overflow-y: auto; background: #1a1a2e; border-radius: 10px; padding: 15px; margin-bottom: 15px; }
        .message { margin-bottom: 15px; padding: 10px; border-radius: 10px; }
        .message.user { background: #533483; margin-left: 20px; }
        .message.ai { background: #16213e; margin-right: 20px; }
        .message.system { background: #0f3460; color: #aaa; font-style: italic; }
        .input-group { display: flex; gap: 10px; }
        .input-group input { flex: 1; padding: 15px; background: #1a1a2e; border: 1px solid #533483; border-radius: 10px; color: #fff; font-size: 16px; }
        .input-group button { padding: 15px 30px; background: #e94560; border: none; border-radius: 10px; color: #fff; font-weight: bold; cursor: pointer; transition: all 0.3s; }
        .input-group button:hover { background: #533483; transform: scale(1.05); }
        .command-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 10px; margin-top: 15px; }
        .command-btn { padding: 10px; background: #16213e; border: 1px solid #533483; border-radius: 8px; color: #fff; cursor: pointer; transition: all 0.3s; font-size: 12px; }
        .command-btn:hover { background: #e94560; transform: translateY(-2px); }
        .tools-section { margin-top: 20px; }
        .access-key { background: #1a1a2e; padding: 15px; border-radius: 10px; font-family: monospace; font-size: 1.2em; text-align: center; margin-bottom: 20px; border: 2px dashed #e94560; }
        .modal { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.8); z-index: 1000; justify-content: center; align-items: center; }
        .modal-content { background: #0f3460; padding: 30px; border-radius: 15px; max-width: 500px; width: 90%; }
        .modal-content input { width: 100%; padding: 15px; margin: 10px 0; background: #1a1a2e; border: 1px solid #533483; border-radius: 10px; color: #fff; }
        .modal-content button { width: 100%; padding: 15px; background: #e94560; border: none; border-radius: 10px; color: #fff; font-weight: bold; cursor: pointer; }
        .troll-section { background: linear-gradient(45deg, #ff6b6b, #ee5a24); }
        .toast { position: fixed; bottom: 20px; right: 20px; background: #e94560; color: #fff; padding: 15px 25px; border-radius: 10px; animation: slideIn 0.3s ease; }
        @keyframes slideIn { from { transform: translateX(100%); } to { transform: translateX(0); } }
    </style>
</head>
<body>
    <div class="modal" id="authModal">
        <div class="modal-content">
            <h2>Enter Access Key</h2>
            <input type="password" id="accessKeyInput" placeholder="Access Key">
            <button onclick="authenticate()">Connect</button>
        </div>
    </div>
    <div class="container">
        <div class="header">
            <h1>🔥 PHONE GATEWAY CONTROLLER 🔥</h1>
        </div>
        <div class="access-key" id="accessKeyDisplay"></div>
        <div class="status-bar">
            <div class="status-card"><h3>Status</h3><div id="deviceStatus">Checking...</div></div>
            <div class="status-card"><h3>Battery</h3><div id="batteryLevel">--%</div></div>
            <div class="status-card"><h3>Device</h3><div id="deviceInfo">Loading...</div></div>
            <div class="status-card"><h3>Network</h3><div id="networkInfo">Checking...</div></div>
        </div>
        <div class="main-panel">
            <div class="panel">
                <h2>🤖 AI Assistant</h2>
                <div class="chat-container" id="chatContainer"></div>
                <div class="input-group">
                    <input type="text" id="aiInput" placeholder="Ask AI or execute command..." onkeypress="if(event.key==='Enter') sendAIMessage()">
                    <button onclick="sendAIMessage()">Send</button>
                </div>
                <div class="tools-section">
                    <h3>Quick Actions</h3>
                    <div class="input-group" style="margin-top: 10px;">
                        <input type="text" id="searchInput" placeholder="Search web...">
                        <button onclick="searchWeb()">🔍 Search</button>
                    </div>
                </div>
            </div>
            <div class="panel">
                <h2>⚡ Command Center</h2>
                <div class="input-group">
                    <input type="text" id="customCommand" placeholder="Custom command...">
                    <button onclick="executeCustom()">Execute</button>
                </div>
                <h3 style="margin-top: 20px;">Basic Controls</h3>
                <div class="command-grid">
                    <button class="command-btn" onclick="execCommand('home')">🏠 Home</button>
                    <button class="command-btn" onclick="execCommand('back')">⬅️ Back</button>
                    <button class="command-btn" onclick="execCommand('recent')">📱 Recent</button>
                    <button class="command-btn" onclick="execCommand('power')">⏻ Power</button>
                    <button class="command-btn" onclick="execCommand('volume_up')">🔊 Vol+</button>
                    <button class="command-btn" onclick="execCommand('volume_down')">🔉 Vol-</button>
                    <button class="command-btn" onclick="execCommand('screenshot')">📸 Screenshot</button>
                    <button class="command-btn" onclick="execCommand('ui_dump')">🔍 UI Dump</button>
                    <button class="command-btn" onclick="execCommand('wifi_on')">📶 WiFi ON</button>
                    <button class="command-btn" onclick="execCommand('wifi_off')">📴 WiFi OFF</button>
                    <button class="command-btn" onclick="execCommand('flashlight_on')">💡 Flash ON</button>
                    <button class="command-btn" onclick="execCommand('flashlight_off')">🔦 Flash OFF</button>
                    <button class="command-btn" onclick="execCommand('location_on')">📍 GPS ON</button>
                    <button class="command-btn" onclick="execCommand('location_off')">🌍 GPS OFF</button>
                    <button class="command-btn" onclick="execCommand('bluetooth_on')">📡 BT ON</button>
                    <button class="command-btn" onclick="execCommand('bluetooth_off')">🔌 BT OFF</button>
                </div>
                <h3 style="margin-top: 20px;">🎮 Advanced</h3>
                <div class="command-grid">
                    <button class="command-btn" onclick="execWithPrompt('tap', 'X Y')">👆 Tap</button>
                    <button class="command-btn" onclick="execWithPrompt('swipe', 'X1 Y1 X2 Y2')">👋 Swipe</button>
                    <button class="command-btn" onclick="execWithPrompt('text', 'Content')">⌨️ Type</button>
                    <button class="command-btn" onclick="execWithPrompt('open_app', 'Package')">📲 Open App</button>
                    <button class="command-btn" onclick="execWithPrompt('open_url', 'URL')">🌐 Open URL</button>
                    <button class="command-btn" onclick="execWithPrompt('youtube', 'Query')">▶️ YouTube</button>
                    <button class="command-btn" onclick="execWithPrompt('google', 'Query')">🔎 Google</button>
                    <button class="command-btn" onclick="execWithPrompt('shell', 'Command')">💻 Shell</button>
                </div>
                <h3 style="margin-top: 20px;">😈 Troll Tools</h3>
                <div class="command-grid">
                    <button class="command-btn" onclick="execCommand('troll_screen_flip')">🌀 Screen Flip</button>
                    <button class="command-btn" onclick="execCommand('troll_screen_normal')">✨ Normal</button>
                    <button class="command-btn" onclick="execCommand('troll_font_huge')">🔤 Huge Font</button>
                    <button class="command-btn" onclick="execCommand('troll_font_normal')">📝 Normal Font</button>
                    <button class="command-btn" onclick="execCommand('troll_spam_notify')">📢 Spam Notify</button>
                    <button class="command-btn" onclick="execCommand('troll_vibrate_crazy')">📳 Crazy Vibrate</button>
                    <button class="command-btn" onclick="execCommand('troll_open_random')">🎲 Random App</button>
                    <button class="command-btn" onclick="execCommand('troll_volume_max')">📢 Max Volume</button>
                    <button class="command-btn" onclick="execCommand('troll_brightness_flash')">💡 Flash Brightness</button>
                </div>
            </div>
        </div>
    </div>
    <script src="/socket.io/socket.io.js"></script>
    <script>
        let socket;
        let accessKey = localStorage.getItem('accessKey');
        const sessionId = localStorage.getItem('sessionId') || (() => { const id = Math.random().toString(36); localStorage.setItem('sessionId', id); return id; })();
        
        function showToast(msg) { const toast = document.createElement('div'); toast.className = 'toast'; toast.textContent = msg; document.body.appendChild(toast); setTimeout(() => toast.remove(), 3000); }
        
        function authenticate() {
            const key = document.getElementById('accessKeyInput').value;
            if (key) {
                accessKey = key;
                localStorage.setItem('accessKey', key);
                document.getElementById('authModal').style.display = 'none';
                connect();
            }
        }
        
        function connect() {
            if (!accessKey) { document.getElementById('authModal').style.display = 'flex'; return; }
            socket = io({ auth: { key: accessKey } });
            socket.on('connect', () => { showToast('Connected!'); loadStatus(); document.getElementById('accessKeyDisplay').textContent = `🔑 Access Key: ${accessKey}`; });
            socket.on('connect_error', () => { localStorage.removeItem('accessKey'); accessKey = null; document.getElementById('authModal').style.display = 'flex'; });
            socket.on('result', (data) => { addMessage('system', `Command: ${data.command}\nResult: ${data.result}`); });
            socket.on('ai_response', (data) => { addMessage('ai', data.response); });
        }
        
        async function loadStatus() {
            try {
                const res = await fetch(`/api/status?key=${accessKey}`);
                const data = await res.json();
                document.getElementById('deviceStatus').textContent = data.status;
                document.getElementById('batteryLevel').textContent = data.battery;
                document.getElementById('deviceInfo').textContent = data.device;
                document.getElementById('accessKeyDisplay').textContent = `🔑 Access Key: ${data.access_key}`;
            } catch(e) {}
        }
        
        function addMessage(role, content) {
            const container = document.getElementById('chatContainer');
            const div = document.createElement('div');
            div.className = `message ${role}`;
            div.textContent = content;
            container.appendChild(div);
            container.scrollTop = container.scrollHeight;
        }
        
        async function sendAIMessage() {
            const input = document.getElementById('aiInput');
            const msg = input.value.trim();
            if (!msg) return;
            addMessage('user', msg);
            input.value = '';
            try {
                const res = await fetch(`/api/ai?key=${accessKey}`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ prompt: msg, session_id: sessionId })
                });
                const data = await res.json();
                addMessage('ai', data.response);
            } catch(e) { addMessage('system', 'Error: ' + e.message); }
        }
        
        async function searchWeb() {
            const input = document.getElementById('searchInput');
            const query = input.value.trim();
            if (!query) return;
            try {
                const res = await fetch(`/api/search?key=${accessKey}`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ query })
                });
                const data = await res.json();
                addMessage('system', `Search: ${query}\n${data.result || 'No results'}`);
            } catch(e) { addMessage('system', 'Error: ' + e.message); }
        }
        
        async function execCommand(cmd, args = '') {
            try {
                const res = await fetch(`/api/command?key=${accessKey}`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ command: cmd, args })
                });
                const data = await res.json();
                addMessage('system', `✓ ${cmd} ${args}\n${data.result}`);
                showToast(`${cmd} executed`);
            } catch(e) { addMessage('system', 'Error: ' + e.message); }
        }
        
        function execWithPrompt(cmd, placeholder) {
            const args = prompt(`Enter ${placeholder}:`);
            if (args) execCommand(cmd, args);
        }
        
        function executeCustom() {
            const input = document.getElementById('customCommand');
            const cmd = input.value.trim();
            if (!cmd) return;
            const parts = cmd.split(' ');
            execCommand(parts[0], parts.slice(1).join(' '));
            input.value = '';
        }
        
        connect();
        setInterval(loadStatus, 5000);
    </script>
</body>
</html>
EOF

echo "[7/7] Creating startup launcher..."
cat > ~/phonegate/start.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
cd ~/phonegate
if ! command -v rish &>/dev/null; then
  shizuku 2>/dev/null
  sleep 2
fi
echo "Starting Phone Gateway..."
echo ""
echo "🌐 Access via: http://$(ip route get 1 | grep -oP 'src \K\S+' 2>/dev/null || ifconfig wlan0 | grep 'inet ' | awk '{print $2}'):3000"
echo ""
node gateway.js
EOF

chmod +x ~/phonegate/start.sh

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "                             ✅ INSTALLATION COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📱 SETUP INSTRUCTIONS:"
echo ""
echo "1. Export Shizuku files:"
echo "   → Open Shizuku app"
echo "   → Tap 'Use Shizuku in terminal apps' → 'Export files'"
echo "   → Select Internal Storage → Shizuku folder"
echo ""
echo "2. Start the gateway:"
echo "   cd ~/phonegate"
echo "   ./start.sh"
echo ""
echo "3. Connect from other devices:"
echo "   → Enable hotspot on this phone"
echo "   → Connect other devices to hotspot"
echo "   → Open browser and go to shown IP address"
echo "   → Enter the access key displayed in terminal"
echo ""
echo "4. Features:"
echo "   🔹 50+ Phone Control Commands"
echo "   🔹 Pollinations AI Chat"
echo "   🔹 Free Web Search"
echo "   🔹 Troll Tools Collection"
echo "   🔹 Real-time Status Updates"
echo "   🔹 Command History"
echo "   🔹 Multi-device Support"
echo ""
echo "5. Commands include:"
echo "   tap, swipe, text, open_app, screenshot, ui_dump, battery,"
echo "   wifi_on/off, bluetooth_on/off, location_on/off, flashlight_on/off,"
echo "   call, sms, open_url, youtube, google, maps, and many more!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
