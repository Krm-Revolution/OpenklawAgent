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
for pkg in curl nodejs git nmap openssl android-tools which termux-api termux-tools iproute2 jq net-tools ffmpeg vlc scrcpy; do
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

check_shizuku() {
    if command -v rish &>/dev/null; then
        if rish -c "echo test" 2>/dev/null | grep -q "test"; then
            return 0
        fi
    fi
    if command -v adb &>/dev/null && adb get-state 1>/dev/null 2>&1; then
        return 0
    fi
    return 1
}

SYSTEM_DIR="$HOME/phone_control_system"
mkdir -p "$SYSTEM_DIR"/{scripts,server,logs,temp,videos}
cd "$SYSTEM_DIR"

cat > scripts/phone_control.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
export PATH="$PATH:/data/data/com.termux/files/usr/bin"

run_cmd() {
    if command -v rish &>/dev/null; then
        rish -c "$*" 2>&1
    elif command -v adb &>/dev/null && adb get-state 1>/dev/null 2>&1; then
        adb shell "$*" 2>&1
    else
        echo "SHIZUKU_NOT_CONNECTED"
        return 1
    fi
}

check_connection() {
    if command -v rish &>/dev/null; then
        rish -c "echo connected" 2>/dev/null | grep -q "connected" && return 0
    fi
    if command -v adb &>/dev/null && adb get-state 1>/dev/null 2>&1; then
        return 0
    fi
    return 1
}

CMD="$1"
shift 2>/dev/null || true

if ! check_connection; then
    echo "SHIZUKU_NOT_CONNECTED"
    exit 1
fi

case "$CMD" in
    screenshot) run_cmd "screencap -p /sdcard/screenshot.png && echo /sdcard/screenshot.png" ;;
    open-app) run_cmd "monkey -p $1 -c android.intent.category.LAUNCHER 1 2>&1" ;;
    youtube-search) 
        QUERY=$(echo "$*" | sed 's/ /+/g')
        run_cmd "am start -a android.intent.action.VIEW -d 'vnd.youtube://results?search_query=$QUERY'"
        ;;
    youtube-play) run_cmd "am start -a android.intent.action.VIEW -d 'vnd.youtube://watch?v=$1'" ;;
    open-url) run_cmd "am start -a android.intent.action.VIEW -d '$1'" ;;
    wifi) 
        if [ "$1" = "on" ]; then 
            run_cmd "svc wifi enable"
        else 
            run_cmd "svc wifi disable"
        fi 
        ;;
    hotspot) 
        if [ "$1" = "on" ]; then 
            run_cmd "svc wifi disable; cmd wifi start-softap"
        else 
            run_cmd "cmd wifi stop-softap"
        fi 
        ;;
    bluetooth) 
        if [ "$1" = "on" ]; then 
            run_cmd "svc bluetooth enable"
        else 
            run_cmd "svc bluetooth disable"
        fi 
        ;;
    nfc) 
        if [ "$1" = "on" ]; then 
            run_cmd "svc nfc enable"
        else 
            run_cmd "svc nfc disable"
        fi 
        ;;
    airplane) 
        if [ "$1" = "on" ]; then 
            run_cmd "settings put global airplane_mode_on 1; am broadcast -a android.intent.action.AIRPLANE_MODE"
        else 
            run_cmd "settings put global airplane_mode_on 0; am broadcast -a android.intent.action.AIRPLANE_MODE"
        fi 
        ;;
    mobile-data) 
        if [ "$1" = "on" ]; then 
            run_cmd "svc data enable"
        else 
            run_cmd "svc data disable"
        fi 
        ;;
    location) 
        if [ "$1" = "on" ]; then 
            run_cmd "settings put secure location_mode 3"
        else 
            run_cmd "settings put secure location_mode 0"
        fi 
        ;;
    battery) run_cmd "dumpsys battery | grep -E 'level|temperature|status'" ;;
    battery-saver) 
        if [ "$1" = "on" ]; then 
            run_cmd "settings put global low_power 1"
        else 
            run_cmd "settings put global low_power 0"
        fi 
        ;;
    brightness) run_cmd "settings put system screen_brightness $1" ;;
    volume) run_cmd "media volume --stream $1 --set $2" ;;
    tap) run_cmd "input tap $1 $2" ;;
    swipe) run_cmd "input swipe $1 $2 $3 $4 ${5:-500}" ;;
    text) 
        TEXT=$(echo "$*" | sed 's/ /%s/g')
        run_cmd "input text '$TEXT'"
        ;;
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
    device-info) 
        MODEL=$(run_cmd "getprop ro.product.model")
        VERSION=$(run_cmd "getprop ro.build.version.release")
        MANUFACTURER=$(run_cmd "getprop ro.product.manufacturer")
        echo "$MODEL|$VERSION|$MANUFACTURER"
        ;;
    memory) run_cmd "dumpsys meminfo | grep -E 'Total RAM|Free RAM'" ;;
    storage) run_cmd "df -h /data" ;;
    processes) run_cmd "ps -A | head -30" ;;
    kill-app) run_cmd "am force-stop $1" ;;
    uninstall-app) run_cmd "pm uninstall $1" ;;
    list-apps) run_cmd "pm list packages -3 | cut -d: -f2" ;;
    open-camera) run_cmd "am start -a android.media.action.IMAGE_CAPTURE" ;;
    open-gallery) run_cmd "am start -a android.intent.action.VIEW -d content://media/external/images/media -t image/*" ;;
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
    file-list) run_cmd "ls -la '$1' 2>/dev/null" ;;
    file-read) run_cmd "cat '$1' 2>/dev/null | head -1000" ;;
    file-delete) run_cmd "rm -rf '$1'" ;;
    file-move) run_cmd "mv '$1' '$2'" ;;
    file-copy) run_cmd "cp -r '$1' '$2'" ;;
    file-mkdir) run_cmd "mkdir -p '$1'" ;;
    open-tiktok) 
        run_cmd "am start -n com.zhiliaoapp.musically/.MainActivity 2>/dev/null || am start -n com.ss.android.ugc.trill/.MainActivity 2>/dev/null || monkey -p com.zhiliaoapp.musically 1"
        ;;
    open-facebook) 
        run_cmd "am start -n com.facebook.katana/.LoginActivity 2>/dev/null || monkey -p com.facebook.katana 1"
        ;;
    open-instagram) 
        run_cmd "am start -n com.instagram.android/.activity.MainTabActivity 2>/dev/null || monkey -p com.instagram.android 1"
        ;;
    open-twitter) 
        run_cmd "am start -n com.twitter.android/.StartActivity 2>/dev/null || monkey -p com.twitter.android 1"
        ;;
    open-whatsapp) 
        run_cmd "am start -n com.whatsapp/.HomeActivity 2>/dev/null || monkey -p com.whatsapp 1"
        ;;
    open-telegram) 
        run_cmd "am start -n org.telegram.messenger/.DefaultIcon 2>/dev/null || monkey -p org.telegram.messenger 1"
        ;;
    open-spotify) 
        run_cmd "am start -n com.spotify.music/.MainActivity 2>/dev/null || monkey -p com.spotify.music 1"
        ;;
    open-netflix) 
        run_cmd "am start -n com.netflix.mediaclient/.UIWebViewActivity 2>/dev/null || monkey -p com.netflix.mediaclient 1"
        ;;
    open-youtube) 
        run_cmd "am start -n com.google.android.youtube/.HomeActivity 2>/dev/null || monkey -p com.google.android.youtube 1"
        ;;
    open-chrome) 
        run_cmd "am start -n com.android.chrome/.Main 2>/dev/null || monkey -p com.android.chrome 1"
        ;;
    open-maps) 
        run_cmd "am start -n com.google.android.apps.maps/.MapsActivity 2>/dev/null || monkey -p com.google.android.apps.maps 1"
        ;;
    open-gmail) 
        run_cmd "am start -n com.google.android.gm/.ConversationListActivityGmail 2>/dev/null || monkey -p com.google.android.gm 1"
        ;;
    open-playstore) run_cmd "am start -a android.intent.action.VIEW -d 'market://details?id=$1'" ;;
    get-clipboard) run_cmd "cmd clipboard get-text 2>/dev/null" ;;
    set-clipboard) run_cmd "cmd clipboard set-text '$*' 2>/dev/null" ;;
    screen-record-start)
        run_cmd "screenrecord --size 720x1280 --bit-rate 4000000 /sdcard/screen_record.mp4 &" &
        echo "Recording started"
        ;;
    screen-record-stop)
        run_cmd "pkill -SIGINT screenrecord"
        sleep 2
        echo "/sdcard/screen_record.mp4"
        ;;
    shell) run_cmd "$*" ;;
    *) echo "Unknown command: $CMD" ;;
esac
EOF
chmod +x scripts/phone_control.sh

cd server
cat > package.json << 'EOFJSON'
{
  "name": "phone-control-server",
  "version": "2.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "latest",
    "socket.io": "latest",
    "fluent-ffmpeg": "latest",
    "axios": "latest",
    "cheerio": "latest",
    "cors": "latest"
  }
}
EOFJSON

npm install --silent

cat > server.js << 'EOFJS'
const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const { exec, spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const axios = require('axios');
const cheerio = require('cheerio');
const cors = require('cors');

const app = express();
app.use(cors());
const server = http.createServer(app);
const io = socketIo(server, { 
    cors: { origin: "*", methods: ["GET", "POST"] },
    maxHttpBufferSize: 1e8,
    transports: ['websocket', 'polling']
});

const PORT = 3000;
const SYSTEM_DIR = path.join(os.homedir(), 'phone_control_system');
const SCRIPTS_DIR = path.join(SYSTEM_DIR, 'scripts');
const LOGS_DIR = path.join(SYSTEM_DIR, 'logs');
const VIDEOS_DIR = path.join(SYSTEM_DIR, 'videos');

const LOG_FILE = path.join(LOGS_DIR, 'phone_control.log');
const HISTORY_FILE = path.join(LOGS_DIR, 'command_history.json');
const CONNECTIONS_FILE = path.join(LOGS_DIR, 'connected_devices.json');

app.use(express.json({ limit: '50mb' }));
app.use(express.static(__dirname));
app.use('/videos', express.static(VIDEOS_DIR));

let connectedDevices = new Map();
let deviceCounter = 0;
let streamProcess = null;
let isStreaming = false;
let streamPort = 8082;
let shizukuAvailable = false;

function checkShizukuStatus() {
    return new Promise((resolve) => {
        exec('bash ' + SCRIPTS_DIR + '/phone_control.sh device-info', { timeout: 5000 }, (error, stdout) => {
            if (error || stdout.includes('SHIZUKU_NOT_CONNECTED')) {
                shizukuAvailable = false;
                resolve(false);
            } else {
                shizukuAvailable = true;
                resolve(true);
            }
        });
    });
}

setInterval(async () => {
    const wasAvailable = shizukuAvailable;
    await checkShizukuStatus();
    if (wasAvailable !== shizukuAvailable) {
        io.emit('shizukuStatus', { available: shizukuAvailable });
        log('Shizuku status changed: ' + (shizukuAvailable ? 'Connected' : 'Disconnected'), 'system');
    }
}, 5000);

try { 
    if(fs.existsSync(CONNECTIONS_FILE)) {
        JSON.parse(fs.readFileSync(CONNECTIONS_FILE,'utf8')).forEach(d => {
            connectedDevices.set(d.id, d);
        });
    }
} catch(e) {}

function saveConnectedDevices() {
    try {
        fs.writeFileSync(CONNECTIONS_FILE, JSON.stringify(Array.from(connectedDevices.values()), null, 2));
    } catch(e) {}
}

function log(message, type, deviceInfo) {
    type = type || 'info';
    deviceInfo = deviceInfo || null;
    const entry = { 
        timestamp: new Date().toISOString(), 
        type: type, 
        message: String(message).substring(0, 500), 
        device: deviceInfo ? { ip: deviceInfo.ip } : null 
    };
    try {
        fs.appendFileSync(LOG_FILE, JSON.stringify(entry) + '\n');
    } catch(e) {}
    io.emit('log', entry);
}

function executeCommand(cmd, deviceInfo) {
    return new Promise((resolve) => {
        if (!shizukuAvailable) {
            resolve('SHIZUKU_NOT_CONNECTED');
            return;
        }
        
        const command = 'bash ' + SCRIPTS_DIR + '/phone_control.sh ' + cmd;
        log('[' + (deviceInfo ? deviceInfo.ip : 'local') + '] ' + cmd, 'command', deviceInfo);
        
        exec(command, { 
            shell: '/data/data/com.termux/files/usr/bin/bash', 
            timeout: 30000,
            maxBuffer: 1024 * 1024 * 10
        }, (error, stdout, stderr) => {
            let result = error ? 'Error: ' + error.message : (stdout || stderr || 'Done');
            if (result.includes('SHIZUKU_NOT_CONNECTED')) {
                shizukuAvailable = false;
                io.emit('shizukuStatus', { available: false });
            }
            const shortResult = result.substring(0, 300);
            log('Result: ' + shortResult, error ? 'error' : 'success', deviceInfo);
            
            let history = [];
            try { 
                if (fs.existsSync(HISTORY_FILE)) {
                    history = JSON.parse(fs.readFileSync(HISTORY_FILE,'utf8')); 
                }
            } catch(e) {}
            history.unshift({ 
                timestamp: new Date().toISOString(), 
                command: cmd, 
                result: shortResult, 
                device: deviceInfo ? deviceInfo.ip : 'local' 
            });
            try {
                fs.writeFileSync(HISTORY_FILE, JSON.stringify(history.slice(0, 100), null, 2));
            } catch(e) {}
            resolve(result);
        });
    });
}

async function aiProcessCommand(userInput, mode) {
    try {
        let systemPrompt = '';
        if (mode === 'chat') {
            systemPrompt = 'You are a helpful AI assistant. Answer questions naturally. Keep responses under 300 characters.';
        } else if (mode === 'search') {
            systemPrompt = 'Extract the main search query from user input. Return ONLY the query terms.';
        } else {
            systemPrompt = 'Convert to phone commands. Available: open-app, youtube-search, youtube-play, wifi, hotspot, bluetooth, airplane, mobile-data, location, battery, brightness, volume, tap, swipe, text, key, home, back, recent, power, volume-up, volume-down, mute, play-pause, next, previous, screen-on, screen-off, camera, open-camera, open-settings, open-tiktok, open-facebook, open-instagram, open-twitter, open-whatsapp, open-telegram, open-spotify, open-netflix, open-youtube, open-chrome, open-maps, open-gmail. For apps: open-tiktok, open-facebook, etc. For YouTube: youtube-search [query] or youtube-play [videoID]. Respond with ONLY the exact command.';
        }
        
        const response = await axios.post('https://text.pollinations.ai/', {
            messages: [
                { role: 'system', content: systemPrompt },
                { role: 'user', content: userInput }
            ],
            model: 'openai',
            temperature: mode === 'chat' ? 0.7 : 0.1,
            max_tokens: 150
        }, { timeout: 10000 });
        
        return response.data;
    } catch(e) {
        return mode === 'chat' ? 'Sorry, I encountered an error.' : null;
    }
}

async function webSearch(query) {
    try {
        const response = await axios.get('https://html.duckduckgo.com/html/?q=' + encodeURIComponent(query), {
            headers: { 'User-Agent': 'Mozilla/5.0' },
            timeout: 10000
        });
        
        const $ = cheerio.load(response.data);
        const results = [];
        
        $('.result').each((i, el) => {
            if (i < 5) {
                const title = $(el).find('.result__title').text().trim();
                const snippet = $(el).find('.result__snippet').text().trim();
                const link = $(el).find('.result__url').text().trim();
                if (title) results.push({ title: title, snippet: snippet, link: link });
            }
        });
        
        return results;
    } catch(e) {
        return [];
    }
}

async function searchYouTube(query) {
    try {
        const response = await axios.get('https://www.youtube.com/results?search_query=' + encodeURIComponent(query), {
            headers: { 'User-Agent': 'Mozilla/5.0' }
        });
        
        const match = response.data.match(/"videoId":"([^"]+)"/);
        return match ? match[1] : null;
    } catch(e) {
        return null;
    }
}

function getLocalIP() {
    const interfaces = os.networkInterfaces();
    for (const name of Object.keys(interfaces)) {
        for (const iface of interfaces[name]) {
            if (iface.family === 'IPv4' && !iface.internal) {
                if (name.includes('wlan') || name.includes('ap') || name.includes('rmnet') || name.includes('eth')) {
                    return iface.address;
                }
            }
        }
    }
    const all = Object.values(interfaces).flat().find(i => i.family === 'IPv4' && !i.internal);
    return all ? all.address : '0.0.0.0';
}

function startScreenStream() {
    return new Promise(async (resolve, reject) => {
        if (!shizukuAvailable) {
            reject(new Error('Shizuku not connected'));
            return;
        }
        
        if (streamProcess) {
            streamProcess.kill();
            streamProcess = null;
        }
        
        const ip = getLocalIP();
        
        exec('bash ' + SCRIPTS_DIR + '/phone_control.sh screen-record-start', async (err) => {
            if (err) {
                reject(err);
                return;
            }
            
            await new Promise(r => setTimeout(r, 2000));
            
            const videoFile = '/sdcard/screen_record.mp4';
            
            streamProcess = spawn('ffmpeg', [
                '-re',
                '-i', videoFile,
                '-c:v', 'libx264',
                '-preset', 'ultrafast',
                '-tune', 'zerolatency',
                '-f', 'mpegts',
                '-r', '30',
                '-g', '60',
                '-b:v', '800k',
                '-maxrate', '800k',
                '-bufsize', '1600k',
                'http://' + ip + ':' + streamPort + '/stream'
            ]);
            
            streamProcess.on('error', (err) => {
                isStreaming = false;
                reject(err);
            });
            
            streamProcess.on('close', () => {
                isStreaming = false;
                io.emit('streamStatus', { active: false });
                exec('bash ' + SCRIPTS_DIR + '/phone_control.sh screen-record-stop');
            });
            
            setTimeout(() => {
                isStreaming = true;
                io.emit('streamStatus', { active: true, url: 'http://' + ip + ':' + streamPort + '/stream' });
                resolve({ active: true, url: 'http://' + ip + ':' + streamPort + '/stream' });
            }, 2000);
        });
    });
}

function stopScreenStream() {
    if (streamProcess) {
        streamProcess.kill();
        streamProcess = null;
    }
    exec('bash ' + SCRIPTS_DIR + '/phone_control.sh screen-record-stop');
    isStreaming = false;
    io.emit('streamStatus', { active: false });
    return { active: false };
}

app.get('/', (req, res) => res.sendFile(path.join(__dirname, 'index.html')));

app.get('/api/status', async (req, res) => {
    await checkShizukuStatus();
    res.json({ 
        shizuku: shizukuAvailable,
        streaming: isStreaming,
        gateway: 'http://' + getLocalIP() + ':' + PORT
    });
});

app.get('/api/logs', (req, res) => {
    try { 
        if (fs.existsSync(LOG_FILE)) {
            const logs = fs.readFileSync(LOG_FILE,'utf8').split('\n').filter(l => l).map(JSON.parse).slice(-200);
            res.json(logs); 
        } else {
            res.json([]);
        }
    } catch(e) { 
        res.json([]); 
    }
});

app.get('/api/device', async (req, res) => {
    if (!shizukuAvailable) {
        res.json({ error: 'SHIZUKU_NOT_CONNECTED' });
        return;
    }
    const info = await executeCommand('device-info');
    const battery = await executeCommand('battery');
    const memory = await executeCommand('memory');
    const storage = await executeCommand('storage');
    res.json({ info: info, battery: battery, memory: memory, storage: storage });
});

app.get('/api/gateway', (req, res) => {
    const ip = getLocalIP();
    res.json({ ip: ip, url: 'http://' + ip + ':' + PORT, port: PORT });
});

app.get('/api/connections', (req, res) => {
    res.json(Array.from(connectedDevices.values()));
});

app.post('/api/command', async (req, res) => {
    const deviceInfo = { 
        ip: req.ip.replace('::ffff:', '').replace('::1', '127.0.0.1'), 
        userAgent: req.get('User-Agent') 
    };
    const result = await executeCommand(req.body.command, deviceInfo);
    res.json({ success: !result.includes('SHIZUKU_NOT_CONNECTED'), result: result });
});

app.post('/api/ai', async (req, res) => {
    const deviceInfo = { 
        ip: req.ip.replace('::ffff:', '').replace('::1', '127.0.0.1'), 
        userAgent: req.get('User-Agent') 
    };
    const prompt = req.body.prompt;
    const mode = req.body.mode;
    
    if (mode === 'search') {
        const searchQuery = await aiProcessCommand(prompt, 'search');
        const results = await webSearch(searchQuery);
        res.json({ success: true, mode: 'search', query: searchQuery, results: results });
    } else {
        const response = await aiProcessCommand(prompt, mode || 'action');
        
        if (mode === 'chat') {
            res.json({ success: true, mode: 'chat', response: response });
        } else {
            const cmd = response.trim();
            if (cmd && !cmd.toLowerCase().includes('sorry') && !cmd.toLowerCase().includes('cannot')) {
                if (cmd.includes('youtube-search')) {
                    const query = cmd.replace('youtube-search', '').trim();
                    const videoId = await searchYouTube(query);
                    if (videoId) {
                        await executeCommand('youtube-play ' + videoId, deviceInfo);
                        res.json({ success: true, mode: 'action', command: cmd, result: 'Playing first YouTube result' });
                    } else {
                        const result = await executeCommand(cmd, deviceInfo);
                        res.json({ success: true, mode: 'action', command: cmd, result: result });
                    }
                } else {
                    const result = await executeCommand(cmd, deviceInfo);
                    res.json({ success: !result.includes('SHIZUKU_NOT_CONNECTED'), mode: 'action', command: cmd, result: result });
                }
            } else {
                res.json({ success: false, message: 'Cannot parse command' });
            }
        }
    }
});

app.post('/api/search', async (req, res) => {
    try {
        const results = await webSearch(req.body.query);
        res.json({ success: true, results: results });
    } catch(e) {
        res.json({ success: false, message: 'Search failed' });
    }
});

app.post('/api/stream/start', async (req, res) => {
    try {
        const result = await startScreenStream();
        res.json({ success: true, active: result.active, url: result.url });
    } catch(e) {
        res.json({ success: false, message: e.message });
    }
});

app.post('/api/stream/stop', (req, res) => {
    const result = stopScreenStream();
    res.json({ success: true, active: result.active });
});

app.get('/api/stream/status', (req, res) => {
    res.json({ active: isStreaming, url: isStreaming ? 'http://' + getLocalIP() + ':' + streamPort + '/stream' : null });
});

app.get('/api/files', async (req, res) => {
    const dir = req.query.path || '/sdcard';
    const result = await executeCommand('file-list "' + dir + '"');
    res.json({ path: dir, files: result });
});

io.on('connection', async (socket) => {
    const deviceInfo = {
        id: 'device_' + (++deviceCounter) + '_' + Date.now(),
        ip: socket.handshake.address.replace('::ffff:', '').replace('::1', '127.0.0.1'),
        userAgent: socket.handshake.headers['user-agent'],
        connectedAt: new Date().toISOString(),
        socketId: socket.id
    };
    
    connectedDevices.set(deviceInfo.id, deviceInfo);
    saveConnectedDevices();
    log('Device connected from ' + deviceInfo.ip, 'system', deviceInfo);
    console.log('[' + new Date().toLocaleTimeString() + '] Device connected: ' + deviceInfo.ip);
    
    await checkShizukuStatus();
    
    io.emit('devicesUpdate', Array.from(connectedDevices.values()));
    socket.emit('shizukuStatus', { available: shizukuAvailable });
    socket.emit('streamStatus', { active: isStreaming, url: isStreaming ? 'http://' + getLocalIP() + ':' + streamPort + '/stream' : null });
    socket.emit('gatewayInfo', { url: 'http://' + getLocalIP() + ':' + PORT });
    
    socket.on('disconnect', () => {
        const device = connectedDevices.get(deviceInfo.id);
        if (device) {
            device.disconnectedAt = new Date().toISOString();
            log('Device disconnected from ' + device.ip, 'system', device);
            console.log('[' + new Date().toLocaleTimeString() + '] Device disconnected: ' + device.ip);
            connectedDevices.delete(deviceInfo.id);
            saveConnectedDevices();
            io.emit('devicesUpdate', Array.from(connectedDevices.values()));
        }
    });
    
    socket.on('getLogs', () => {
        try { 
            if (fs.existsSync(LOG_FILE)) {
                const logs = fs.readFileSync(LOG_FILE,'utf8').split('\n').filter(l => l).map(JSON.parse).slice(-100);
                socket.emit('logs', logs); 
            } else {
                socket.emit('logs', []);
            }
        } catch(e) {
            socket.emit('logs', []);
        }
    });
    
    socket.on('command', async (cmd) => {
        const result = await executeCommand(cmd, deviceInfo);
        socket.emit('commandResult', { command: cmd, result: result });
    });
    
    socket.on('getGateway', () => {
        socket.emit('gatewayInfo', { url: 'http://' + getLocalIP() + ':' + PORT });
    });
    
    socket.on('startStream', async () => {
        try {
            await startScreenStream();
            socket.emit('streamStarted', { url: 'http://' + getLocalIP() + ':' + streamPort + '/stream' });
        } catch(e) {
            socket.emit('streamError', e.message);
        }
    });
    
    socket.on('stopStream', () => {
        stopScreenStream();
        socket.emit('streamStopped');
    });
    
    socket.on('checkShizuku', async () => {
        await checkShizukuStatus();
        socket.emit('shizukuStatus', { available: shizukuAvailable });
    });
});

const streamServer = http.createServer((req, res) => {
    if (req.url === '/stream') {
        res.writeHead(200, {
            'Content-Type': 'video/mp2t',
            'Access-Control-Allow-Origin': '*',
            'Cache-Control': 'no-cache, no-store, must-revalidate',
            'Connection': 'keep-alive'
        });
        
        if (streamProcess && streamProcess.stdout) {
            streamProcess.stdout.pipe(res);
            streamProcess.stdout.on('end', () => res.end());
        } else {
            res.end();
        }
    } else {
        res.writeHead(404);
        res.end();
    }
});

streamServer.listen(streamPort);

checkShizukuStatus().then(() => {
    server.listen(PORT, '0.0.0.0', () => {
        const ip = getLocalIP();
        log('Server started - Gateway: http://' + ip + ':' + PORT, 'system');
        console.log('\nGateway URL: http://' + ip + ':' + PORT);
        console.log('Shizuku Status: ' + (shizukuAvailable ? 'Connected' : 'Not Connected - Gateway disabled'));
        console.log('');
    });
});
EOFJS

cat > index.html << 'EOFHTML'
<!DOCTYPE html>
<html><head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=yes">
<title>Phone Control System</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#0a0e27;min-height:100vh;color:#fff}
.container{max-width:100%;margin:0 auto;padding:12px}
.gateway-banner{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);border-radius:20px;padding:20px;margin-bottom:20px}
.gateway-url{font-size:clamp(16px,5vw,28px);font-weight:bold;font-family:monospace;background:rgba(0,0,0,0.3);padding:12px 16px;border-radius:12px;display:inline-block;margin:10px 0;word-break:break-all}
.copy-btn{background:rgba(255,255,255,0.2);border:none;color:#fff;padding:10px 20px;border-radius:10px;cursor:pointer;margin-left:10px}
.shizuku-warning{background:#ef4444;border-radius:16px;padding:16px;margin-bottom:20px;display:none}
.shizuku-warning.show{display:block}
.nav-bar{display:flex;gap:6px;margin-bottom:20px;flex-wrap:wrap;background:rgba(255,255,255,0.05);border-radius:16px;padding:10px}
.nav-btn{background:rgba(255,255,255,0.1);border:1px solid rgba(255,255,255,0.15);color:#fff;padding:12px 16px;border-radius:12px;font-size:13px;cursor:pointer;flex:1;min-width:90px}
.nav-btn.active{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%)}
.page{display:none}
.page.active{display:block}
.devices-panel{background:rgba(255,255,255,0.05);border-radius:16px;padding:16px;margin-bottom:16px}
.device-item{display:flex;align-items:center;gap:10px;padding:10px;background:rgba(255,255,255,0.05);border-radius:10px;margin-bottom:6px}
.device-online{width:10px;height:10px;border-radius:50%;background:#4ade80;animation:pulse 2s infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:0.5}}
.status-bar{display:flex;gap:10px;margin-bottom:16px;flex-wrap:wrap}
.status-item{background:rgba(255,255,255,0.08);padding:10px 18px;border-radius:30px;display:flex;align-items:center;gap:8px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:14px;margin-bottom:14px}
.card{background:rgba(255,255,255,0.05);border-radius:18px;padding:18px}
h2{font-size:17px;margin-bottom:14px}
.btn-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(75px,1fr));gap:8px}
button{background:rgba(255,255,255,0.1);border:1px solid rgba(255,255,255,0.15);color:#fff;padding:12px 10px;border-radius:12px;font-size:12px;cursor:pointer;display:flex;flex-direction:column;align-items:center;gap:5px}
button:disabled{opacity:0.3;cursor:not-allowed}
button:hover:not(:disabled){background:rgba(255,255,255,0.2)}
.input-group{display:flex;gap:8px;margin-top:12px}
input{flex:1;padding:12px;border:none;border-radius:12px;background:rgba(255,255,255,0.1);color:#fff;font-size:14px;border:1px solid rgba(255,255,255,0.15)}
input:disabled{opacity:0.5}
.log-container{background:rgba(0,0,0,0.3);border-radius:12px;padding:12px;max-height:280px;overflow-y:auto;font-family:monospace;font-size:11px}
.log-entry{padding:5px 0;border-bottom:1px solid rgba(255,255,255,0.08)}
.log-time{color:#64b5f6}
.log-success{color:#81c784}
.log-error{color:#e57373}
.log-system{color:#ffd54f}
.chat-container{height:400px;overflow-y:auto;margin-bottom:14px;padding:14px;background:rgba(0,0,0,0.2);border-radius:14px}
.chat-message{margin-bottom:12px;padding:12px 16px;border-radius:18px;max-width:85%;word-break:break-word}
.chat-user{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);margin-left:auto}
.chat-bot{background:rgba(255,255,255,0.1);margin-right:auto}
.stream-container{background:#000;border-radius:16px;overflow:hidden;aspect-ratio:16/9}
.stream-video{width:100%;height:100%;object-fit:contain}
.file-list{max-height:450px;overflow-y:auto}
.file-item{display:flex;align-items:center;gap:10px;padding:12px;border-bottom:1px solid rgba(255,255,255,0.08);cursor:pointer}
.file-item:hover{background:rgba(255,255,255,0.08)}
.search-result{background:rgba(255,255,255,0.05);border-radius:12px;padding:14px;margin-bottom:10px;cursor:pointer}
.search-result:hover{background:rgba(255,255,255,0.1)}
</style>
</head><body>
<div class="container">
<div class="gateway-banner" id="gatewayBanner">
<h2>Gateway Access URL</h2>
<div><span class="gateway-url" id="gatewayUrl">Checking...</span><button class="copy-btn" onclick="copyGatewayUrl()">Copy</button></div>
<p style="margin-top:12px;opacity:0.9;font-size:14px">Connect to hotspot and open this URL</p>
</div>

<div class="shizuku-warning" id="shizukuWarning">
<h3>⚠️ Shizuku Not Connected</h3>
<p>Please enable Shizuku or ADB debugging on your device. Gateway URL and controls are disabled.</p>
</div>

<div class="nav-bar">
<button class="nav-btn active" onclick="switchPage('main')">Main</button>
<button class="nav-btn" onclick="switchPage('ai')">AI</button>
<button class="nav-btn" onclick="switchPage('search')">Search</button>
<button class="nav-btn" onclick="switchPage('files')">Files</button>
<button class="nav-btn" onclick="switchPage('stream')">Stream</button>
<button class="nav-btn" onclick="switchPage('settings')">Settings</button>
</div>

<div id="main-page" class="page active">
<div class="devices-panel">
<h3>Connected Devices <span id="deviceCount">(0)</span></h3>
<div id="devicesList"><div class="device-item" style="justify-content:center;opacity:0.7">No devices connected</div></div>
</div>
<div class="status-bar">
<div class="status-item"><span id="shizukuDot" style="width:10px;height:10px;border-radius:50%;background:#ef4444"></span><span id="shizukuStatus">Checking...</span></div>
<div class="status-item"><span id="deviceModel">Loading...</span></div>
<div class="status-item"><span id="batteryLevel">--%</span></div>
</div>
<div class="grid">
<div class="card"><h2>Navigation</h2><div class="btn-grid">
<button onclick="sendCmd('home')">Home</button>
<button onclick="sendCmd('back')">Back</button>
<button onclick="sendCmd('recent')">Recent</button>
<button onclick="sendCmd('notification')">Notify</button>
</div></div>
<div class="card"><h2>Media</h2><div class="btn-grid">
<button onclick="sendCmd('volume-up')">Vol+</button>
<button onclick="sendCmd('volume-down')">Vol-</button>
<button onclick="sendCmd('mute')">Mute</button>
<button onclick="sendCmd('play-pause')">Play</button>
<button onclick="sendCmd('next')">Next</button>
<button onclick="sendCmd('previous')">Prev</button>
</div></div>
</div>
<div class="grid">
<div class="card"><h2>Power</h2><div class="btn-grid">
<button onclick="sendCmd('power')">Power</button>
<button onclick="sendCmd('screen-on')">Screen On</button>
<button onclick="sendCmd('screen-off')">Screen Off</button>
<button onclick="sendCmd('lock')">Lock</button>
<button onclick="sendCmd('sleep')">Sleep</button>
<button onclick="sendCmd('wake')">Wake</button>
</div></div>
<div class="card"><h2>Network</h2><div class="btn-grid">
<button onclick="sendCmd('wifi on')">WiFi On</button>
<button onclick="sendCmd('wifi off')">WiFi Off</button>
<button onclick="sendCmd('hotspot on')">Hotspot On</button>
<button onclick="sendCmd('hotspot off')">Hotspot Off</button>
<button onclick="sendCmd('bluetooth on')">BT On</button>
<button onclick="sendCmd('bluetooth off')">BT Off</button>
</div></div>
</div>
<div class="grid">
<div class="card"><h2>Apps</h2><div class="btn-grid">
<button onclick="sendCmd('open-tiktok')">TikTok</button>
<button onclick="sendCmd('open-facebook')">Facebook</button>
<button onclick="sendCmd('open-instagram')">Instagram</button>
<button onclick="sendCmd('open-twitter')">Twitter</button>
<button onclick="sendCmd('open-whatsapp')">WhatsApp</button>
<button onclick="sendCmd('open-telegram')">Telegram</button>
<button onclick="sendCmd('open-spotify')">Spotify</button>
<button onclick="sendCmd('open-netflix')">Netflix</button>
<button onclick="sendCmd('open-youtube')">YouTube</button>
<button onclick="sendCmd('open-chrome')">Chrome</button>
<button onclick="sendCmd('open-maps')">Maps</button>
<button onclick="sendCmd('open-gmail')">Gmail</button>
</div></div>
<div class="card"><h2>Input</h2><div class="input-group">
<input type="number" id="tapX" placeholder="X" value="500" style="width:80px">
<input type="number" id="tapY" placeholder="Y" value="500" style="width:80px">
<button onclick="sendCmd('tap '+tapX.value+' '+tapY.value)">Tap</button>
</div>
<div class="input-group">
<input type="text" id="textInput" placeholder="Type text...">
<button onclick="sendCmd('text '+textInput.value);textInput.value=''">Type</button>
</div></div>
</div>
<div class="card"><h2>Command Log</h2>
<div class="input-group">
<input type="text" id="customCommand" placeholder="Enter command...">
<button onclick="sendCmd(customCommand.value);customCommand.value=''">Execute</button>
</div>
<div class="log-container" id="logContainer"></div>
</div>
</div>

<div id="ai-page" class="page">
<div class="card"><h2>AI Agent</h2>
<div class="btn-grid" style="margin-bottom:15px">
<button class="nav-btn active" onclick="setAIMode('chat')">Chat</button>
<button class="nav-btn" onclick="setAIMode('action')">Action</button>
<button class="nav-btn" onclick="setAIMode('search')">Search</button>
</div>
<div class="chat-container" id="chatContainer"></div>
<div class="input-group">
<input type="text" id="aiInput" placeholder="Ask me anything..." onkeypress="if(event.key==='Enter')sendAIMessage()">
<button onclick="sendAIMessage()">Send</button>
</div>
</div>
</div>

<div id="search-page" class="page">
<div class="card"><h2>Web Search</h2>
<div class="input-group">
<input type="text" id="searchInput" placeholder="Search..." onkeypress="if(event.key==='Enter')webSearch()">
<button onclick="webSearch()">Search</button>
</div>
<div id="searchResults" style="margin-top:15px"></div>
</div>
</div>

<div id="files-page" class="page">
<div class="card"><h2>File Manager</h2>
<div class="input-group">
<input type="text" id="currentPath" value="/sdcard" placeholder="Path">
<button onclick="loadFiles(currentPath.value)">Browse</button>
<button onclick="loadFiles('/sdcard')">SDCard</button>
<button onclick="loadFiles('/')">Root</button>
</div>
<div class="file-list" id="fileList"></div>
</div>
</div>

<div id="stream-page" class="page">
<div class="card"><h2>Screen Stream</h2>
<div class="btn-grid" style="margin-bottom:15px">
<button onclick="startStream()">Start Streaming</button>
<button onclick="stopStream()">Stop Streaming</button>
</div>
<div class="stream-container">
<video id="streamVideo" class="stream-video" autoplay muted playsinline></video>
</div>
<div id="streamUrl" style="margin-top:15px;font-family:monospace;word-break:break-all"></div>
</div>
</div>

<div id="settings-page" class="page">
<div class="grid">
<div class="card"><h2>System Settings</h2><div class="btn-grid">
<button onclick="sendCmd('open-settings')">Settings</button>
<button onclick="sendCmd('open-wifi-settings')">WiFi</button>
<button onclick="sendCmd('open-bluetooth-settings')">Bluetooth</button>
<button onclick="sendCmd('open-app-settings')">Apps</button>
<button onclick="sendCmd('open-display-settings')">Display</button>
<button onclick="sendCmd('open-sound-settings')">Sound</button>
<button onclick="sendCmd('open-storage-settings')">Storage</button>
<button onclick="sendCmd('open-battery-settings')">Battery</button>
</div></div>
<div class="card"><h2>Device Info</h2><div id="deviceInfo"></div></div>
</div>
</div>
</div>

<script src="/socket.io/socket.io.js"></script>
<script>
const socket = io({transports: ['websocket', 'polling']});
let currentPage = 'main';
let currentAIMode = 'chat';
let shizukuConnected = false;

function switchPage(page) {
    document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
    document.querySelectorAll('.nav-btn').forEach(b => b.classList.remove('active'));
    document.getElementById(page + '-page').classList.add('active');
    event.target.classList.add('active');
    currentPage = page;
    if (page === 'stream') checkStreamStatus();
    if (page === 'settings') loadDeviceInfo();
}

function setAIMode(mode) {
    currentAIMode = mode;
    document.querySelectorAll('#ai-page .nav-btn').forEach(b => b.classList.remove('active'));
    event.target.classList.add('active');
}

function updateShizukuUI(available) {
    shizukuConnected = available;
    const warning = document.getElementById('shizukuWarning');
    const banner = document.getElementById('gatewayBanner');
    const dot = document.getElementById('shizukuDot');
    const status = document.getElementById('shizukuStatus');
    
    if (available) {
        warning.classList.remove('show');
        banner.style.opacity = '1';
        dot.style.background = '#4ade80';
        status.textContent = 'Shizuku Connected';
    } else {
        warning.classList.add('show');
        banner.style.opacity = '0.5';
        dot.style.background = '#ef4444';
        status.textContent = 'Shizuku Disconnected';
    }
    
    document.querySelectorAll('button').forEach(b => {
        if (!b.classList.contains('nav-btn') && b.id !== 'shizukuCheck') {
            b.disabled = !available;
        }
    });
}

function sendCmd(cmd) {
    if (!shizukuConnected) {
        addLog({timestamp: new Date().toISOString(), type: 'error', message: 'Cannot execute: Shizuku not connected'});
        return;
    }
    socket.emit('command', cmd);
    addLog({timestamp: new Date().toISOString(), type: 'command', message: cmd});
}

async function sendAIMessage() {
    const input = document.getElementById('aiInput');
    const message = input.value.trim();
    if (!message) return;
    
    addChatMessage('user', message);
    input.value = '';
    
    try {
        const res = await fetch('/api/ai', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({prompt: message, mode: currentAIMode})
        });
        const data = await res.json();
        
        if (data.success) {
            if (data.mode === 'chat') {
                addChatMessage('bot', data.response);
            } else if (data.mode === 'search') {
                addChatMessage('bot', 'Searching: ' + data.query);
                displaySearchResults(data.results);
            } else {
                addChatMessage('bot', data.command + '\n' + (data.result || 'Done'));
            }
        } else {
            addChatMessage('bot', data.message || 'Error');
        }
    } catch(e) {
        addChatMessage('bot', 'Connection error');
    }
}

function addChatMessage(role, text) {
    const container = document.getElementById('chatContainer');
    const div = document.createElement('div');
    div.className = 'chat-message chat-' + role;
    div.textContent = text;
    container.appendChild(div);
    container.scrollTop = container.scrollHeight;
}

async function webSearch() {
    const input = document.getElementById('searchInput');
    const query = input.value.trim();
    if (!query) return;
    
    try {
        const res = await fetch('/api/search', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({query: query})
        });
        const data = await res.json();
        displaySearchResults(data.results);
    } catch(e) {}
}

function displaySearchResults(results) {
    const container = document.getElementById('searchResults');
    if (!results || results.length === 0) {
        container.innerHTML = '<p>No results</p>';
        return;
    }
    container.innerHTML = results.map(r => 
        '<div class="search-result" onclick="window.open(\'https://' + r.link + '\', \'_blank\')">' +
            '<div style="font-weight:bold">' + r.title + '</div>' +
            '<div style="font-size:12px;opacity:0.7">' + r.link + '</div>' +
            '<div style="font-size:13px">' + r.snippet + '</div>' +
        '</div>'
    ).join('');
}

async function loadFiles(path) {
    try {
        const res = await fetch('/api/files?path=' + encodeURIComponent(path));
        const data = await res.json();
        document.getElementById('currentPath').value = data.path;
        
        const list = document.getElementById('fileList');
        list.innerHTML = '';
        
        if (path !== '/') {
            const parent = path.split('/').slice(0, -1).join('/') || '/';
            const div = document.createElement('div');
            div.className = 'file-item';
            div.innerHTML = '<span>📁 ..</span>';
            div.onclick = () => loadFiles(parent);
            list.appendChild(div);
        }
        
        if (data.files && !data.files.includes('SHIZUKU_NOT_CONNECTED')) {
            data.files.split('\n').forEach(f => {
                if (!f.trim()) return;
                const parts = f.trim().split(/\s+/);
                if (parts.length < 9) return;
                
                const perms = parts[0];
                const name = parts.slice(8).join(' ');
                if (name === '.' || name === '..') return;
                
                const isDir = perms.startsWith('d');
                const div = document.createElement('div');
                div.className = 'file-item';
                div.innerHTML = '<span>' + (isDir ? '📁' : '📄') + ' ' + name + '</span>';
                div.onclick = () => isDir ? loadFiles(path + '/' + name) : null;
                list.appendChild(div);
            });
        }
    } catch(e) {}
}

async function startStream() {
    if (!shizukuConnected) return;
    try {
        const res = await fetch('/api/stream/start', {method: 'POST'});
        const data = await res.json();
        if (data.success) {
            document.getElementById('streamUrl').textContent = 'Stream URL: ' + data.url;
            const video = document.getElementById('streamVideo');
            video.src = data.url;
            video.play().catch(() => {});
        }
    } catch(e) {}
}

async function stopStream() {
    try {
        await fetch('/api/stream/stop', {method: 'POST'});
        document.getElementById('streamUrl').textContent = '';
        document.getElementById('streamVideo').src = '';
    } catch(e) {}
}

async function checkStreamStatus() {
    try {
        const res = await fetch('/api/stream/status');
        const data = await res.json();
        if (data.active) {
            document.getElementById('streamUrl').textContent = 'Stream URL: ' + data.url;
            const video = document.getElementById('streamVideo');
            if (video.src !== data.url) {
                video.src = data.url;
                video.play().catch(() => {});
            }
        }
    } catch(e) {}
}

async function loadDeviceInfo() {
    if (!shizukuConnected) return;
    try {
        const res = await fetch('/api/device');
        const data = await res.json();
        if (data.error) return;
        const info = data.info.split('|');
        document.getElementById('deviceInfo').innerHTML = 
            '<p>Model: ' + (info[0] || 'Unknown') + '</p>' +
            '<p>Android: ' + (info[1] || 'Unknown') + '</p>' +
            '<p>Manufacturer: ' + (info[2] || 'Unknown') + '</p>' +
            '<p>' + data.battery + '</p>';
    } catch(e) {}
}

function addLog(l) {
    const container = document.getElementById('logContainer');
    const div = document.createElement('div');
    div.className = 'log-entry';
    div.innerHTML = '<span class="log-time">[' + new Date(l.timestamp).toLocaleTimeString() + ']</span> <span class="log-' + l.type + '">' + l.message + '</span>';
    container.appendChild(div);
    container.scrollTop = container.scrollHeight;
    if (container.children.length > 50) container.removeChild(container.children[0]);
}

async function copyGatewayUrl() {
    const url = document.getElementById('gatewayUrl').textContent;
    if (url && url !== 'Checking...' && url !== 'Disabled') {
        try {
            await navigator.clipboard.writeText(url);
            alert('Copied!');
        } catch(e) {
            prompt('Copy:', url);
        }
    }
}

socket.on('connect', () => {
    socket.emit('getLogs');
    socket.emit('getGateway');
    socket.emit('checkShizuku');
});

socket.on('shizukuStatus', status => {
    updateShizukuUI(status.available);
    if (status.available) {
        loadMainInfo();
        loadDeviceInfo();
    }
});

socket.on('log', addLog);
socket.on('logs', logs => {
    document.getElementById('logContainer').innerHTML = '';
    logs.reverse().forEach(addLog);
});
socket.on('commandResult', d => {
    addLog({timestamp: new Date().toISOString(), type: 'success', message: d.command + ': ' + d.result});
});
socket.on('gatewayInfo', info => {
    document.getElementById('gatewayUrl').textContent = shizukuConnected ? info.url : 'Disabled';
});
socket.on('devicesUpdate', devices => {
    document.getElementById('deviceCount').textContent = '(' + devices.length + ')';
    document.getElementById('devicesList').innerHTML = devices.length ? 
        devices.map(d => '<div class="device-item"><span class="device-online"></span><span>' + d.ip + '</span></div>').join('') :
        '<div class="device-item" style="justify-content:center;opacity:0.7">No devices</div>';
});
socket.on('streamStatus', status => {
    if (status.active) {
        document.getElementById('streamUrl').textContent = 'Stream URL: ' + status.url;
        const video = document.getElementById('streamVideo');
        if (video.src !== status.url) {
            video.src = status.url;
            video.play().catch(() => {});
        }
    } else {
        document.getElementById('streamUrl').textContent = '';
    }
});

async function loadMainInfo() {
    if (!shizukuConnected) return;
    try {
        const r = await fetch('/api/device');
        const d = await r.json();
        if (d.error) return;
        const i = d.info.split('|');
        document.getElementById('deviceModel').textContent = (i[0] || 'Android') + ' ' + (i[1] || '');
        const b = d.battery.match(/level: (\d+)/);
        if (b) document.getElementById('batteryLevel').textContent = b[1] + '%';
    } catch(e) {}
}

setInterval(() => { if (shizukuConnected) loadMainInfo(); }, 30000);
setInterval(checkStreamStatus, 5000);
setInterval(() => socket.emit('checkShizuku'), 10000);
</script>
</body></html>
EOFHTML

mkdir -p ~/.termux/boot
cat > ~/.termux/boot/start-phone-server << EOF
#!/data/data/com.termux/files/usr/bin/bash
cd $SYSTEM_DIR/server
npm install --silent 2>/dev/null
node server.js > /dev/null 2>&1 &
EOF
chmod +x ~/.termux/boot/start-phone-server

cat > "$SYSTEM_DIR/view_connections.sh" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
echo "Connected Devices Log"
echo "================================================"
if [ -f ~/phone_control_system/logs/connected_devices.json ]; then
    cat ~/phone_control_system/logs/connected_devices.json | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));if(d.length===0){console.log('No devices')}else{d.forEach((x,i)=>{console.log((i+1)+'. IP: '+x.ip);console.log('   Connected: '+new Date(x.connectedAt).toLocaleString());if(x.disconnectedAt)console.log('   Disconnected: '+new Date(x.disconnectedAt).toLocaleString());console.log('')})}"
else
    echo "No connections yet"
fi
EOF
chmod +x "$SYSTEM_DIR/view_connections.sh"

echo ""
echo "================================================"
echo "CHECKING SHIZUKU CONNECTION..."
echo "================================================"

if check_shizuku; then
    echo "✅ Shizuku is connected!"
    
    bash "$SYSTEM_DIR/scripts/phone_control.sh" hotspot on 2>/dev/null || true
    sleep 3
    
    GATEWAY_IP=$(ip route get 1 2>/dev/null | grep -oP 'src \K\S+' | head -1)
    if [ -z "$GATEWAY_IP" ]; then
        GATEWAY_IP=$(ifconfig wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}')
    fi
    if [ -z "$GATEWAY_IP" ]; then
        GATEWAY_IP="192.168.43.1"
    fi
    
    echo ""
    echo "================================================"
    echo "✅ INSTALLATION COMPLETE!"
    echo "================================================"
    echo ""
    echo "Gateway URL: http://$GATEWAY_IP:3000"
    echo ""
    echo "Copy this URL to other devices on this hotspot!"
    echo "================================================"
    echo ""
    echo "Starting server..."
    echo ""
    
    cd "$SYSTEM_DIR/server"
    node server.js
else
    echo "❌ Shizuku is NOT connected!"
    echo ""
    echo "Please enable Shizuku or ADB debugging:"
    echo "1. Install Shizuku app from Play Store"
    echo "2. Enable Developer Options and USB Debugging"
    echo "3. Start Shizuku service"
    echo "4. Re-run this script"
    echo ""
    echo "================================================"
    echo ""
    echo "Starting server in LIMITED mode (no device control)..."
    echo ""
    
    cd "$SYSTEM_DIR/server"
    node server.js
fi
