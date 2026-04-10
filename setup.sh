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
echo "║         🥹 REMOTE PHONE CONTROL SYSTEM AUTO-INSTALLER        ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

pkg update -y -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" </dev/null 2>&1 || true
for pkg in curl nodejs git nmap openssl android-tools which termux-api termux-tools iproute2 jq net-tools ffmpeg vlc; do
    pkg install -y $pkg </dev/null 2>&1 || true
done

if ! grep -q "NODE_OPTIONS=--dns-result-order=ipv4first" ~/.bashrc 2>/dev/null; then
    echo "export NODE_OPTIONS=--dns-result-order=ipv4first" >> ~/.bashrc
fi
export NODE_OPTIONS=--dns-result-order=ipv4first

if [ ! -d "$HOME/storage" ]; then
    echo "y" | termux-setup-storage >/dev/null 2>&1 || true
    sleep 2
fi

SHIZUKU_DIR="$HOME/storage/shared/Shizuku"
mkdir -p "$SHIZUKU_DIR" 2>/dev/null || true

if [ ! -f "$SHIZUKU_DIR/rish_shizuku.dex" ]; then
    curl -L -o "$SHIZUKU_DIR/rish_shizuku.dex" "https://github.com/RikkaApps/Shizuku/releases/latest/download/rish_shizuku.dex" 2>/dev/null || true
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
    bash "$SHIZUKU_DIR/copy.sh" </dev/null 2>/dev/null
fi

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
  pattern-lock) run_cmd "input keyevent 26; input keyevent 82; input swipe 200 800 600 800 100; input swipe 600 800 600 1200 100; input swipe 600 1200 200 1200 100; input swipe 200 1200 200 1600 100" ;;
  pin-unlock) run_cmd "input text '$1'; input keyevent 66" ;;
  password-unlock) run_cmd "input text '$1'; input keyevent 66" ;;
  open-camera) run_cmd "am start -a android.media.action.IMAGE_CAPTURE" ;;
  open-video) run_cmd "am start -a android.media.action.VIDEO_CAPTURE" ;;
  open-gallery) run_cmd "am start -a android.intent.action.VIEW -d content://media/external/images/media -t image/*" ;;
  open-music) run_cmd "am start -a android.intent.action.VIEW -d content://media/external/audio/media -t audio/*" ;;
  open-files) run_cmd "am start -a android.intent.action.VIEW -d content://com.android.externalstorage.documents/root" ;;
  open-settings) run_cmd "am start -a android.settings.SETTINGS" ;;
  open-wifi-settings) run_cmd "am start -a android.settings.WIFI_SETTINGS" ;;
  open-bluetooth-settings) run_cmd "am start -a android.settings.BLUETOOTH_SETTINGS" ;;
  open-app-settings) run_cmd "am start -a android.settings.APPLICATION_SETTINGS" ;;
  open-developer-settings) run_cmd "am start -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS" ;;
  open-display-settings) run_cmd "am start -a android.settings.DISPLAY_SETTINGS" ;;
  open-sound-settings) run_cmd "am start -a android.settings.SOUND_SETTINGS" ;;
  open-storage-settings) run_cmd "am start -a android.settings.INTERNAL_STORAGE_SETTINGS" ;;
  open-battery-settings) run_cmd "am start -a android.intent.action.POWER_USAGE_SUMMARY" ;;
  open-security-settings) run_cmd "am start -a android.settings.SECURITY_SETTINGS" ;;
  open-accounts-settings) run_cmd "am start -a android.settings.SYNC_SETTINGS" ;;
  open-language-settings) run_cmd "am start -a android.settings.LOCALE_SETTINGS" ;;
  open-date-settings) run_cmd "am start -a android.settings.DATE_SETTINGS" ;;
  open-accessibility-settings) run_cmd "am start -a android.settings.ACCESSIBILITY_SETTINGS" ;;
  open-print-settings) run_cmd "am start -a android.settings.PRINT_SETTINGS" ;;
  open-vpn-settings) run_cmd "am start -a android.net.vpn.SETTINGS" ;;
  open-nfc-settings) run_cmd "am start -a android.settings.NFC_SETTINGS" ;;
  take-photo) run_cmd "am start -a android.media.action.IMAGE_CAPTURE; sleep 2; input keyevent 27; input keyevent 27" ;;
  record-video) run_cmd "am start -a android.media.action.VIDEO_CAPTURE; sleep 2; input keyevent 27; sleep 5; input keyevent 27" ;;
  play-media) run_cmd "am start -a android.intent.action.VIEW -d '$1' -t video/*" ;;
  open-contacts) run_cmd "am start -a android.intent.action.VIEW content://contacts/people" ;;
  open-calendar) run_cmd "am start -a android.intent.action.VIEW content://com.android.calendar" ;;
  open-calculator) run_cmd "am start -a android.intent.action.MAIN -n com.android.calculator2/.Calculator" ;;
  open-clock) run_cmd "am start -a android.intent.action.MAIN -n com.android.deskclock/.DeskClock" ;;
  open-messages) run_cmd "am start -a android.intent.action.MAIN -n com.google.android.apps.messaging/.ui.ConversationListActivity" ;;
  open-phone) run_cmd "am start -a android.intent.action.MAIN -n com.android.dialer/.DialtactsActivity" ;;
  open-chrome) run_cmd "am start -a android.intent.action.MAIN -n com.android.chrome/.Main" ;;
  open-playstore) run_cmd "am start -a android.intent.action.VIEW -d market://details?id=$1" ;;
  install-apk) run_cmd "pm install -r $1" ;;
  uninstall-package) run_cmd "pm uninstall $1" ;;
  clear-cache) run_cmd "pm clear $1" ;;
  force-stop) run_cmd "am force-stop $1" ;;
  start-service) run_cmd "am startservice $1" ;;
  stop-service) run_cmd "am stopservice $1" ;;
  broadcast) run_cmd "am broadcast -a $1" ;;
  get-clipboard) run_cmd "cmd clipboard get-text" 2>/dev/null ;;
  set-clipboard) run_cmd "cmd clipboard set-text '$*'" 2>/dev/null ;;
  file-list) run_cmd "ls -la $1" ;;
  file-read) run_cmd "cat $1" ;;
  file-delete) run_cmd "rm -rf $1" ;;
  file-move) run_cmd "mv $1 $2" ;;
  file-copy) run_cmd "cp -r $1 $2" ;;
  file-mkdir) run_cmd "mkdir -p $1" ;;
  download-file) run_cmd "curl -L -o $1 $2" ;;
  upload-file) run_cmd "curl -F 'file=@$1' $2" ;;
  ui-dump) 
    run_cmd "uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1"
    node -e "const fs=require('fs');try{const x=fs.readFileSync('/sdcard/window_dump.xml','utf8');const r=/(?:text|content-desc)=\"([^\"]+)\"[^>]*bounds=\"(\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\])\"/g;let m;while((m=r.exec(x))!==null){if(m[1].trim()!=='')console.log(m[2]+' '+m[1]);}}catch(e){}" 2>/dev/null
    ;;
  shell) run_cmd "$*" ;;
  *) echo "Unknown command: $CMD" ;;
esac
EOF
chmod +x ~/phone_control.sh

mkdir -p ~/phone_server
cd ~/phone_server
npm init -y >/dev/null 2>&1
npm install express socket.io fluent-ffmpeg duck-duck-scrape >/dev/null 2>&1

cat > ~/phone_server/server.js << 'EOFJS'
const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const { exec, spawn } = require('child_process');
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
let castProcess = null;
let isCasting = false;

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
    exec(command, { shell: '/data/data/com.termux/files/usr/bin/bash', timeout: 60000 }, (error, stdout, stderr) => {
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

async function aiProcessCommand(userInput, mode) {
  try {
    let systemPrompt = '';
    if (mode === 'chat') {
      systemPrompt = 'You are a helpful AI assistant. Answer questions naturally and conversationally.';
    } else {
      systemPrompt = `You are a phone control AI. Convert user requests into phone_control.sh commands.
Available commands: screenshot, open-app, open-url, youtube-search, wifi, hotspot, bluetooth, nfc, airplane, mobile-data, location, battery, battery-saver, brightness, volume, tap, swipe, text, key, home, back, recent, power, menu, volume-up, volume-down, mute, play-pause, next, previous, screen-on, screen-off, camera, notification, quick-settings, sleep, wake, reboot, lock, device-info, memory, storage, processes, kill-app, uninstall-app, list-apps, pattern-lock, pin-unlock, password-unlock, open-camera, open-video, open-gallery, open-music, open-files, open-settings, open-wifi-settings, open-bluetooth-settings, open-app-settings, open-developer-settings, open-display-settings, open-sound-settings, open-storage-settings, open-battery-settings, open-security-settings, open-accounts-settings, open-language-settings, open-date-settings, open-accessibility-settings, open-print-settings, open-vpn-settings, open-nfc-settings, take-photo, record-video, play-media, open-contacts, open-calendar, open-calculator, open-clock, open-messages, open-phone, open-chrome, open-playstore, install-apk, uninstall-package, clear-cache, force-stop, start-service, stop-service, broadcast, get-clipboard, set-clipboard, file-list, file-read, file-delete, file-move, file-copy, file-mkdir, download-file, upload-file, ui-dump, shell.
Respond with ONLY the exact command.`;
    }
    
    const res = await fetch('https://text.pollinations.ai/', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        messages: [{ role: 'system', content: systemPrompt }, { role: 'user', content: userInput }],
        model: 'openai',
        temperature: mode === 'chat' ? 0.7 : 0.1
      })
    });
    return await res.text();
  } catch(e) { return mode === 'chat' ? 'Sorry, I encountered an error.' : null; }
}

async function duckDuckGoSearch(query) {
  try {
    const response = await fetch(`https://api.duckduckgo.com/?q=${encodeURIComponent(query)}&format=json&no_html=1&skip_disambig=1`);
    const data = await response.json();
    let result = '';
    if (data.Abstract) result += data.Abstract + '\n\n';
    if (data.Answer) result += data.Answer + '\n\n';
    if (data.RelatedTopics && data.RelatedTopics.length > 0) {
      result += 'Related:\n';
      data.RelatedTopics.slice(0, 5).forEach(t => { if(t.Text) result += `- ${t.Text}\n`; });
    }
    return result || 'No results found.';
  } catch(e) { return 'Search failed. Check internet connection.'; }
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

function startCasting() {
  return new Promise((resolve, reject) => {
    if (castProcess) {
      castProcess.kill();
      castProcess = null;
    }
    const ip = getHotspotIP();
    const screenCapture = spawn('adb', ['exec-out', 'screenrecord', '--output-format=h264', '-']);
    castProcess = spawn('ffmpeg', [
      '-i', 'pipe:0',
      '-f', 'mpegts',
      '-vcodec', 'mpeg1video',
      '-s', '1280x720',
      '-b:v', '1000k',
      '-r', '30',
      '-bf', '0',
      '-codec:v', 'mpeg1video',
      `http://${ip}:8082/screen`
    ]);
    screenCapture.stdout.pipe(castProcess.stdin);
    castProcess.on('error', (err) => {
      reject(err);
    });
    castProcess.on('close', () => {
      isCasting = false;
      io.emit('castStatus', { active: false });
    });
    isCasting = true;
    io.emit('castStatus', { active: true, url: `http://${ip}:8082/screen` });
    resolve({ active: true, url: `http://${ip}:8082/screen` });
  });
}

function stopCasting() {
  if (castProcess) {
    castProcess.kill();
    castProcess = null;
  }
  isCasting = false;
  io.emit('castStatus', { active: false });
  return { active: false };
}

app.get('/', (req, res) => res.sendFile(path.join(__dirname, 'index.html')));
app.get('/api/logs', (req, res) => {
  try { res.json(fs.readFileSync(LOG_FILE,'utf8').split('\n').filter(l=>l).map(JSON.parse).slice(-200)); } catch(e) { res.json([]); }
});
app.get('/api/device', async (req, res) => {
  res.json({ info: await executeCommand('device-info'), battery: await executeCommand('battery'), memory: await executeCommand('memory'), storage: await executeCommand('storage') });
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
  const { prompt, mode } = req.body;
  const response = await aiProcessCommand(prompt, mode || 'action');
  if (mode === 'chat') {
    res.json({ success: true, mode: 'chat', response });
  } else {
    const cmd = response;
    if (cmd && !cmd.includes('sorry') && !cmd.includes('cannot')) {
      res.json({ success: true, mode: 'action', command: cmd, result: await executeCommand(cmd, deviceInfo) });
    } else {
      res.json({ success: false, message: 'Cannot parse command' });
    }
  }
});
app.post('/api/search', async (req, res) => {
  try {
    const result = await duckDuckGoSearch(req.body.query);
    res.json({ success: true, result });
  } catch(e) { res.json({ success: false, message: 'Search failed' }); }
});
app.post('/api/cast/start', async (req, res) => {
  try {
    const result = await startCasting();
    res.json({ success: true, ...result });
  } catch(e) { res.json({ success: false, message: e.message }); }
});
app.post('/api/cast/stop', (req, res) => {
  res.json({ success: true, ...stopCasting() });
});
app.get('/api/cast/status', (req, res) => {
  res.json({ active: isCasting, url: isCasting ? `http://${getHotspotIP()}:8082/screen` : null });
});
app.get('/api/files', async (req, res) => {
  const dir = req.query.path || '/sdcard';
  const result = await executeCommand(`file-list ${dir}`);
  res.json({ path: dir, files: result });
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
  log(`🥹 Device connected from ${deviceInfo.ip}`, 'system', deviceInfo);
  console.log(`🥹 [${new Date().toLocaleTimeString()}] Device connected: ${deviceInfo.ip}`);
  io.emit('devicesUpdate', Array.from(connectedDevices.values()));
  socket.emit('castStatus', { active: isCasting, url: isCasting ? `http://${getHotspotIP()}:8082/screen` : null });
  
  socket.on('disconnect', () => {
    const device = connectedDevices.get(deviceInfo.id);
    if (device) {
      device.disconnectedAt = new Date().toISOString();
      log(`🥹 Device disconnected from ${device.ip}`, 'system', device);
      console.log(`🥹 [${new Date().toLocaleTimeString()}] Device disconnected: ${device.ip}`);
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
  
  socket.on('getGateway', () => socket.emit('gatewayInfo', { url: `http://${getHotspotIP()}:${PORT}` }));
  
  socket.on('startCast', async () => {
    try {
      await startCasting();
      socket.emit('castStarted', { url: `http://${getHotspotIP()}:8082/screen` });
    } catch(e) { socket.emit('castError', e.message); }
  });
  
  socket.on('stopCast', () => {
    stopCasting();
    socket.emit('castStopped');
  });
});

server.listen(PORT, '0.0.0.0', () => {
  const ip = getHotspotIP();
  log(`🥹 Server started - Gateway: http://${ip}:${PORT}`, 'system');
  console.log(`\n🥹 Gateway URL: http://${ip}:${PORT}\n`);
});

const castServer = http.createServer((req, res) => {
  res.writeHead(200, {
    'Content-Type': 'video/mp2t',
    'Access-Control-Allow-Origin': '*',
    'Cache-Control': 'no-cache'
  });
  if (castProcess) {
    castProcess.stdout.pipe(res);
  } else {
    res.end();
  }
});
castServer.listen(8082);
EOFJS

cat > ~/phone_server/index.html << 'EOFHTML'
<!DOCTYPE html>
<html><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=yes">
<title>🥹 Phone Control</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:linear-gradient(135deg,#1a1a2e 0%,#16213e 50%,#0f3460 100%);min-height:100vh;padding:16px;color:#fff}
.container{max-width:1400px;margin:0 auto}
.nav-bar{display:flex;gap:8px;margin-bottom:20px;flex-wrap:wrap;background:rgba(255,255,255,0.1);backdrop-filter:blur(10px);border-radius:16px;padding:12px;border:1px solid rgba(255,255,255,0.1)}
.nav-btn{background:rgba(255,255,255,0.15);border:1px solid rgba(255,255,255,0.2);color:#fff;padding:12px 20px;border-radius:10px;font-size:14px;font-weight:500;cursor:pointer;transition:all 0.2s;flex:1;min-width:120px}
.nav-btn.active{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%)}
.nav-btn:hover{background:rgba(255,255,255,0.25);transform:translateY(-2px)}
.page{display:none}
.page.active{display:block}
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
input,select,textarea{flex:1;padding:10px 12px;border:none;border-radius:10px;background:rgba(255,255,255,0.15);color:#fff;font-size:14px;border:1px solid rgba(255,255,255,0.2)}
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
.chat-container{height:400px;overflow-y:auto;margin-bottom:12px;padding:12px;background:rgba(0,0,0,0.2);border-radius:10px}
.chat-message{margin-bottom:12px;padding:8px 12px;border-radius:10px;max-width:80%}
.chat-user{background:rgba(102,126,234,0.3);margin-left:auto;text-align:right}
.chat-bot{background:rgba(255,255,255,0.1);margin-right:auto}
.cast-screen{background:#000;border-radius:10px;padding:0;overflow:hidden}
.cast-video{width:100%;max-height:500px;object-fit:contain}
.file-list{max-height:400px;overflow-y:auto}
.file-item{display:flex;align-items:center;gap:8px;padding:8px;border-bottom:1px solid rgba(255,255,255,0.1);cursor:pointer}
.file-item:hover{background:rgba(255,255,255,0.1)}
</style>
</head><body>
<div class="container">
<div class="gateway-banner"><h2 style="margin-bottom:8px">🥹 Gateway Access URL</h2><div><span class="gateway-url" id="gatewayUrl">Loading...</span><button class="copy-btn" onclick="copyGatewayUrl()">📋 Copy</button></div><p style="margin-top:12px;opacity:0.9">Connect to this hotspot and open this URL</p></div>

<div class="nav-bar">
<button class="nav-btn active" onclick="switchPage('main')">🏠 Main Control</button>
<button class="nav-btn" onclick="switchPage('ai')">🤖 AI Agent</button>
<button class="nav-btn" onclick="switchPage('search')">🔍 Web Search</button>
<button class="nav-btn" onclick="switchPage('files')">📁 File Manager</button>
<button class="nav-btn" onclick="switchPage('cast')">📺 Screen Cast</button>
<button class="nav-btn" onclick="switchPage('settings')">⚙️ Settings</button>
</div>

<div id="main-page" class="page active">
<div class="devices-panel"><h3>📱 Connected Devices <span id="deviceCount">(0)</span></h3><div id="devicesList"><div class="device-item" style="justify-content:center;opacity:0.7">No devices connected</div></div></div>
<div class="status-bar"><div class="status-item"><span class="connection-dot"></span><span id="connectionStatus">Connected</span></div><div class="status-item"><span id="deviceModel">Loading...</span></div><div class="status-item"><span id="batteryLevel">🔋 --%</span></div></div>
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
<div class="grid">
<div class="card"><h2>🎯 Touch Control</h2><div class="input-group"><input type="number" id="tapX" placeholder="X" value="500"><input type="number" id="tapY" placeholder="Y" value="500"><button onclick="send('tap '+tapX.value+' '+tapY.value)">Tap</button></div>
<div class="input-group"><input type="text" id="textInput" placeholder="Type text..."><button onclick="send('text '+textInput.value);textInput.value=''">Type</button></div>
</div>
<div class="card"><h2>📸 Camera & Media</h2><div class="btn-grid">
<button onclick="send('open-camera')"><svg viewBox="0 0 24 24"><path d="M9 3L7.17 5H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2h-3.17L15 3H9z"/></svg>Camera</button>
<button onclick="send('open-video')"><svg viewBox="0 0 24 24"><path d="M17 10.5V7c0-.55-.45-1-1-1H4c-.55 0-1 .45-1 1v10c0 .55.45 1 1 1h12c.55 0 1-.45 1-1v-3.5l4 4v-11l-4 4z"/></svg>Video</button>
<button onclick="send('open-gallery')"><svg viewBox="0 0 24 24"><path d="M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2z"/></svg>Gallery</button>
<button onclick="send('open-music')"><svg viewBox="0 0 24 24"><path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z"/></svg>Music</button>
</div></div>
</div>
<div class="card"><h2>📝 Command Log</h2><div class="input-group"><input type="text" id="customCommand" placeholder="Enter command..."><button onclick="send(customCommand.value);customCommand.value=''">Execute</button></div><div class="log-container" id="logContainer"></div></div>
</div>

<div id="ai-page" class="page">
<div class="grid">
<div class="card"><h2>🤖 AI Agent Mode</h2><div class="btn-grid" style="margin-bottom:12px"><button class="nav-btn active" onclick="setAIMode('chat')">💬 Chat Mode</button><button class="nav-btn" onclick="setAIMode('action')">⚡ Action Mode</button></div>
<div class="chat-container" id="chatContainer"></div>
<div class="input-group"><input type="text" id="aiInput" placeholder="Ask me anything..."><button onclick="sendAIMessage()">Send</button></div></div>
</div>
</div>

<div id="search-page" class="page">
<div class="card"><h2>🔍 DuckDuckGo Web Search</h2><div class="input-group"><input type="text" id="searchInput" placeholder="Search the web..."><button onclick="webSearch()">Search</button></div><div id="searchResult" style="margin-top:12px;max-height:500px;overflow-y:auto;font-size:14px;white-space:pre-wrap"></div></div>
</div>

<div id="files-page" class="page">
<div class="card"><h2>📁 File Manager</h2><div class="input-group"><input type="text" id="currentPath" value="/sdcard" placeholder="Path"><button onclick="loadFiles(currentPath.value)">Browse</button></div><div class="file-list" id="fileList"></div></div>
</div>

<div id="cast-page" class="page">
<div class="card"><h2>📺 Screen Cast</h2><div class="btn-grid" style="margin-bottom:12px"><button onclick="startCast()">▶️ Start Casting</button><button onclick="stopCast()">⏹️ Stop Casting</button></div>
<div class="cast-screen"><video id="castVideo" class="cast-video" autoplay muted playsinline></video></div>
<div id="castUrl" style="margin-top:12px;font-family:monospace"></div></div>
</div>

<div id="settings-page" class="page">
<div class="grid">
<div class="card"><h2>⚙️ System Settings</h2><div class="btn-grid">
<button onclick="send('open-settings')">Main Settings</button>
<button onclick="send('open-wifi-settings')">WiFi</button>
<button onclick="send('open-bluetooth-settings')">Bluetooth</button>
<button onclick="send('open-app-settings')">Apps</button>
<button onclick="send('open-developer-settings')">Developer</button>
<button onclick="send('open-display-settings')">Display</button>
<button onclick="send('open-sound-settings')">Sound</button>
<button onclick="send('open-storage-settings')">Storage</button>
<button onclick="send('open-battery-settings')">Battery</button>
<button onclick="send('open-security-settings')">Security</button>
<button onclick="send('open-accounts-settings')">Accounts</button>
<button onclick="send('open-language-settings')">Language</button>
<button onclick="send('open-date-settings')">Date & Time</button>
<button onclick="send('open-accessibility-settings')">Accessibility</button>
<button onclick="send('open-print-settings')">Print</button>
<button onclick="send('open-vpn-settings')">VPN</button>
<button onclick="send('open-nfc-settings')">NFC</button>
</div></div>
<div class="card"><h2>🔓 Unlock Methods</h2><div class="btn-grid">
<button onclick="send('pattern-lock')">Pattern Unlock</button>
<button onclick="sendPin()">PIN Unlock</button>
</div></div>
<div class="card"><h2>📊 Device Info</h2><div id="deviceInfo"></div></div>
</div>
</div>
</div>

<script src="/socket.io/socket.io.js"></script>
<script>
const socket=io();
let currentPage='main';
let currentAIMode='chat';
let chatHistory=[];

function switchPage(page){
document.querySelectorAll('.page').forEach(p=>p.classList.remove('active'));
document.querySelectorAll('.nav-btn').forEach(b=>b.classList.remove('active'));
document.getElementById(page+'-page').classList.add('active');
event.target.classList.add('active');
currentPage=page;
if(page==='cast')checkCastStatus();
if(page==='settings')loadDeviceInfo();
}

function setAIMode(mode){
currentAIMode=mode;
document.querySelectorAll('#ai-page .nav-btn').forEach(b=>b.classList.remove('active'));
event.target.classList.add('active');
}

async function sendAIMessage(){
const input=document.getElementById('aiInput');
const message=input.value.trim();
if(!message)return;
addChatMessage('user',message);
input.value='';
try{
const res=await fetch('/api/ai',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({prompt:message,mode:currentAIMode})});
const data=await res.json();
if(data.success){
if(data.mode==='chat'){addChatMessage('bot',data.response);}
else{addChatMessage('bot',`✅ ${data.command}\n${data.result}`);}
}else{addChatMessage('bot','❌ '+data.message);}
}catch(e){addChatMessage('bot','❌ Error');}
}

function addChatMessage(role,text){
const container=document.getElementById('chatContainer');
const div=document.createElement('div');
div.className='chat-message chat-'+role;
div.textContent=text;
container.appendChild(div);
container.scrollTop=container.scrollHeight;
}

async function webSearch(){
const input=document.getElementById('searchInput');
const query=input.value.trim();
if(!query)return;
addLog({timestamp:new Date().toISOString(),type:'system',message:`Search: ${query}`});
try{
const res=await fetch('/api/search',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({query})});
const data=await res.json();
document.getElementById('searchResult').textContent=data.result;
}catch(e){document.getElementById('searchResult').textContent='Search failed';}
}

async function loadFiles(path){
try{
const res=await fetch('/api/files?path='+encodeURIComponent(path));
const data=await res.json();
const list=document.getElementById('fileList');
list.innerHTML='';
if(data.files){
data.files.split('\n').forEach(f=>{
if(!f)return;
const div=document.createElement('div');
div.className='file-item';
div.innerHTML=`<span>📄 ${f}</span>`;
div.onclick=()=>{
const newPath=path+'/'+f;
document.getElementById('currentPath').value=newPath;
loadFiles(newPath);
};
list.appendChild(div);
});
}
}catch(e){}
}

let castActive=false;

async function startCast(){
try{
const res=await fetch('/api/cast/start',{method:'POST'});
const data=await res.json();
if(data.success){
castActive=true;
document.getElementById('castUrl').textContent='Cast URL: '+data.url;
const video=document.getElementById('castVideo');
video.src=data.url;
video.play().catch(()=>{});
}else{alert('Cast failed');}
}catch(e){alert('Cast error');}
}

async function stopCast(){
try{
await fetch('/api/cast/stop',{method:'POST'});
castActive=false;
document.getElementById('castUrl').textContent='';
const video=document.getElementById('castVideo');
video.pause();
video.src='';
}catch(e){}
}

async function checkCastStatus(){
try{
const res=await fetch('/api/cast/status');
const data=await res.json();
castActive=data.active;
if(data.active){
document.getElementById('castUrl').textContent='Cast URL: '+data.url;
const video=document.getElementById('castVideo');
if(video.src!==data.url){
video.src=data.url;
video.play().catch(()=>{});
}
}
}catch(e){}
}

async function loadDeviceInfo(){
try{
const res=await fetch('/api/device');
const data=await res.json();
document.getElementById('deviceInfo').innerHTML=`
<p>Model: ${data.info.split('\n')[2]||'Unknown'}</p>
<p>Android: ${data.info.split('\n')[1]||'Unknown'}</p>
<p>Battery: ${data.battery}</p>
<p>Memory: ${data.memory}</p>
`;
}catch(e){}
}

function sendPin(){
const pin=prompt('Enter PIN:');
if(pin)send('pin-unlock '+pin);
}

function send(cmd){socket.emit('command',cmd);}

function addLog(l){
const container=document.getElementById('logContainer');
const d=document.createElement('div');
d.className='log-entry';
d.innerHTML=`<span class="log-time">[${new Date(l.timestamp).toLocaleTimeString()}]</span> <span class="log-${l.type}">${l.device?`[${l.device.ip}] `:''}${l.message}</span>`;
container.appendChild(d);
container.scrollTop=container.scrollHeight;
}

async function copyGatewayUrl(){
const url=document.getElementById('gatewayUrl').textContent;
await navigator.clipboard.writeText(url);
alert('Gateway URL copied!');
}

socket.on('connect',()=>{
document.getElementById('connectionStatus').textContent='Connected';
socket.emit('getLogs');
socket.emit('getGateway');
loadMainInfo();
});

socket.on('log',addLog);
socket.on('logs',logs=>{document.getElementById('logContainer').innerHTML='';logs.reverse().forEach(addLog);});
socket.on('commandResult',d=>{addLog({timestamp:new Date().toISOString(),type:'success',message:`${d.command}: ${d.result}`});});
socket.on('gatewayInfo',info=>{document.getElementById('gatewayUrl').textContent=info.url;});
socket.on('devicesUpdate',devices=>{
document.getElementById('deviceCount').textContent=`(${devices.length})`;
document`;
document.getElementById('.getElementById('devicesdevicesList').List').innerHTML=devices.lengthinnerHTML=devices.length?devices.map(d=>`<?devices.map(d=>`<div classdiv class="device-item"><="device-item"><span class="devicespan class="device-online-online"></span"></span><span style="><spanflex: style="flex:1">${d1">${d.ip}</span><.ip}</span><span stylespan style="font="font-size:-size:11px11px;opacity:;opacity:0.5">${new0.5"> Date(d.connected${new Date(dAt)..connectedAt).toLocaleTimetoLocaleTimeString()}</String()}</span></div>`span></).join(''div>`).join):'(''):'<div class<div class="device-item" style="device-item" style="justify-content="justify-content:center;op:center;opacity:acity:0.0.7">7">No devicesNo devices connected</ connected</div>';
});
socketdiv>';
});
socket.on('.on('castStatus',status=>{
castStatus',status=>{
castActivecastActive=status.active;
=statusif(status.active;
if(status.active){
document.getElementById.active){
document.getElementById('cast('castUrl').textContent='Cast URL:Url').textContent='Cast URL: '+status '+status.url;
.url;
const videoconst video=document=document.getElementById('.getElementById('castVideo');
ifcastVideo');
if(video(video.src!==status.url){
.src!==status.url){
video.srcvideo.src=status=status.url;
video.play.url;
video.play().catch().catch(()=>{});
}
}else{
document(()=>{});
}
}else{
document.getElementById('castUrl').text.getElementById('castUrl').textContent='';
const video=Content='';
const video=document.getElementById('castVideo');
document.getElementById('castVideo');
video.pvideo.pause();
video.srcause();
video.src='';
}
});

='';
}
});

async functionasync function loadMainInfo(){
try{
 loadMainInfo(){
const r=awaittry{
const r=await fetch('/api/ fetch('/api/device');
const ddevice');
const d=await r.json=await r.json();
const();
const i=d i=d.info.split('\n');
document.info.split('\n');
document.getElementById('.getElementById('deviceModeldeviceModel').text').textContent=`${i[2Content=`${i[2]||'Android'} ${i]||'Android'} ${i[1][1]||''}`;
||''}`;
const b=d.bconst b=d.battery.matchattery.match(/level: (\(/level: (\d+)/);
d+)/);
if(b)documentif(b).getElementById('document.getElementById('batteryLevel').batteryLevel').textContent=`textContent=`🔋 ${b[1]}🔋 ${b%`;
}catch[1]}(e){%`;
}catch(e){}
}

}
}

setIntervalsetInterval(loadMainInfo(loadMainInfo,30000);
setInterval(checkCastStatus,5000,30000);
setInterval(checkCastStatus,5000);
loadMainInfo);
loadMainInfo();
</script>
();
</script>
</body</body></html></html>
EOF>
EOFHTML

mkdir -p ~HTML

mkdir -p ~/.termux/boot
/.termux/boot
cat > ~/.cat > ~/.termux/boottermux/start-phone/boot/start-phone-server <<-server << 'EOF 'EOF'
#!/data/data'
#!/data/data/com.termux/com.termux/files//files/usr/bin/bash
cd ~usr/bin/bash
cd ~/phone_server
/phone_server
npm installnpm install --silent express socket.io --silent express socket.io fluent-ffm fluent-ffmpeg duck-duckpeg duck-duck-scrape-scrape 2>/dev 2>/dev/null
/null
node server.js >node server.js > /dev /dev/null /null 2>&2>&1 &
EOF
1 &
EOF
chmodchmod +x +x ~/. ~/.termuxtermux/boot/boot/start-phone-server

/start-phonecat >-server

cat > ~/ ~/view_connections.sh << 'view_connections.sh << 'EOF'
EOF'
#!/data#!/data/data/com/data/com.term.termux/files/usrux/files/usr/bin/bash/bin/bash
echo "
echo🥹 Connected Devices "🥹 Connected Log"
echo "━━ Devices Log"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if━━"
 [ -fif [ -f ~/ ~/connected_devconnected_devices.json ]; thenices.json
    cat ~ ]; then
    cat ~/connected/connected_devices_devices.json |.json | node -e " node -const de "const d=JSON.parse(=JSON.parse(require('fs').require('fsreadFile').readFileSync(Sync(0,'0,'utf8utf8'));'));if(dif(d.length===0){console.log.length===0){('No devices')console.log('No}else devices')}else{d.forEach{d.forEach((x,i)=((x,i)=>{console.log(\`\>{console.log(\`\${i${i+1+1}. IP: \}. IP: \${x${x.ip}\.ip}\`);console.log(\``);console.log(\`   Connected: \   Connected: \${new${new Date(x Date(x.connected.connectedAt).toLocaleString()At).toLocaleString()}\`}\`);if(x.dis);if(x.disconnectedAt)console.log(\connectedAt)console.log(\`  `   Disconnected Disconnected: \${new: \${new Date(x.disconnectedAt). Date(x.disconnectedAt).toLocaletoLocaleString()String()}\`);console}\`);console.log('')}).log('')})}"
else
    echo "}"
else
    echo "No connectionsNo connections yet"
 yet"
fi
echo ""
fi
echo ""
echo "📋echo "📋 Live Log:"
 Live Log:"
tail -tail -f ~/phonef ~/phone_control.log |_control.log | grep --line-b grep --line-buffereduffered "Device "Device"
EOF"
EOF
ch
chmod +mod +x ~/viewx ~_connections.sh

/view_connections.sh

cd ~/phonecd ~/phone_server
_server
npm installnpm install --silent express --silent express socket.io socket.io fluent-ffmpeg duck fluent-ffmpeg duck-duck-duck-scrape 2-scrape 2>/dev/null

>/dev/null

GATEGATEWAY_WAY_IP=$(ip route get IP=$(ip route1  get 1 2>/2>/dev/null | grepdev/null -o | grep -oP 'src \K\P 'src \K\S+' |S+' head -1 | head -1)
if [ -z "$)
if [ -GATEz "$GATEWAY_WAY_IP"IP" ]; then ]; then
   
    GATE GATEWAY_WAY_IP=$(IP=$(ifconfig wlanifconfig wlan0 2>/0 2>/dev/null | grepdev/null | grep 'inet ' | 'inet ' | awk '{ awk '{print $2}')
print $2}')
fi
fi
ifif [ -z "$G [ -z "$GATEWAYATEWAY_IP_IP" ];" ]; then
 then
    G    GATEWAYATEWAY__IP="192IP="192.168.43.168.43.1.1"
fi"
fi

~/

~/phone_phone_control.shcontrol.sh hotspot on hotspot on 2 2>/dev/null || true
>/dev/null || true
sleep 3

echo ""
sleep 3

echo ""
echo "echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo"
echo "🥹 AUTO "🥹 AUTO-INST-INSTALLATION COMPLETE!"
ALLATION COMPLecho "ETE!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo"
echo ""
echo ""
echo "🥹 "🥹 Gateway URL Gateway URL: http://: http://$G$GATEWAYATEWAY_IP_IP:300:3000"
0"
echo ""
echo ""
echo "echo "📋📋 Copy this Copy this URL to URL to other devices on this other devices on this hotspot hotspot!"
echo "━━━━!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo"
echo ""
echo " "🚀 Starting server..."
echo "🚀 Starting server..."
echo ""

node"

node server.js server.js
