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
echo "║                    v2.0 - Fixed Version                      ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

pkg update -y -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" </dev/null 2>&1 || true
for pkg in curl nodejs git nmap openssl android-tools which termux-api termux-tools iproute2 jq net-tools ffmpeg; do
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

SYSTEM_DIR="$HOME/phone_control_system"
mkdir -p "$SYSTEM_DIR"/{scripts,server,logs,temp}
cd "$SYSTEM_DIR"

cat > scripts/phone_control.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
export PATH="$PATH:/data/data/com.termux/files/usr/bin"

check_shizuku() {
    if command -v rish &>/dev/null; then
        if rish -c "echo test" &>/dev/null; then
            return 0
        fi
    fi
    if command -v adb &>/dev/null; then
        if adb get-state 1>/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

run_cmd() {
    if ! check_shizuku; then
        echo "ERROR: Shizuku/ADB not running or not connected"
        return 1
    fi
    
    if command -v rish &>/dev/null && rish -c "echo test" &>/dev/null 2>&1; then
        rish -c "$*" 2>&1
    elif command -v adb &>/dev/null && adb get-state 1>/dev/null 2>&1; then
        adb shell "$*" 2>&1
    else
        echo "ERROR: No valid execution method available"
        return 1
    fi
}

get_package_name() {
    local app="$1"
    case "$app" in
        tiktok) echo "com.zhiliaoapp.musically" ;;
        facebook) echo "com.facebook.katana" ;;
        instagram) echo "com.instagram.android" ;;
        twitter|x) echo "com.twitter.android" ;;
        whatsapp) echo "com.whatsapp" ;;
        telegram) echo "org.telegram.messenger" ;;
        spotify) echo "com.spotify.music" ;;
        netflix) echo "com.netflix.mediaclient" ;;
        youtube) echo "com.google.android.youtube" ;;
        chrome) echo "com.android.chrome" ;;
        gmail) echo "com.google.android.gm" ;;
        maps) echo "com.google.android.apps.maps" ;;
        *) echo "$app" ;;
    esac
}

open_app_safe() {
    local app_name="$1"
    local package=$(get_package_name "$app_name")
    
    if ! check_shizuku; then
        echo "ERROR: Shizuku not running"
        return 1
    fi
    
    local result=$(run_cmd "pm list packages | grep -i '$package'")
    if [ -z "$result" ]; then
        echo "ERROR: App not installed: $package"
        return 1
    fi
    
    run_cmd "monkey -p $package -c android.intent.category.LAUNCHER 1" 2>&1
    if [ $? -eq 0 ]; then
        echo "SUCCESS: Opened $app_name"
        return 0
    else
        run_cmd "am start -n $package/.MainActivity" 2>&1 || \
        run_cmd "am start -n $package/.ui.activities.MainActivity" 2>&1 || \
        run_cmd "am start $(run_cmd "cmd package resolve-activity --brief $package | tail -n 1")" 2>&1
        return $?
    fi
}

CMD="$1"
shift 2>/dev/null || true

case "$CMD" in
    check-shizuku)
        if check_shizuku; then
            echo "SHIZUKU_OK"
        else
            echo "SHIZUKU_NOT_RUNNING"
        fi
        ;;
    screenshot) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "screencap -p '${1:-/sdcard/screenshot.png}'" 
        ;;
    open-app) 
        open_app_safe "$1"
        ;;
    youtube-search) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        QUERY=$(echo "$*" | sed 's/ /+/g')
        run_cmd "am start -a android.intent.action.VIEW -d 'vnd.youtube://results?search_query=$QUERY'" || \
        run_cmd "am start -a android.intent.action.VIEW 'https://www.youtube.com/results?search_query=$QUERY'"
        sleep 2
        run_cmd "input keyevent 20 && sleep 0.5 && input keyevent 20 && sleep 0.5 && input keyevent 23"
        ;;
    youtube-play) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "am start -a android.intent.action.VIEW -d 'vnd.youtube://watch?v=$1'" || \
        run_cmd "am start -a android.intent.action.VIEW 'https://www.youtube.com/watch?v=$1'"
        ;;
    open-url) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "am start -a android.intent.action.VIEW -d '$1'" 
        ;;
    wifi) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        if [ "$1" = "on" ]; then run_cmd "svc wifi enable"; else run_cmd "svc wifi disable"; fi 
        ;;
    hotspot) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        if [ "$1" = "on" ]; then 
            run_cmd "svc wifi disable && sleep 1 && cmd wifi start-softap"
        else 
            run_cmd "cmd wifi stop-softap"
        fi 
        ;;
    bluetooth) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        if [ "$1" = "on" ]; then run_cmd "svc bluetooth enable"; else run_cmd "svc bluetooth disable"; fi 
        ;;
    nfc) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        if [ "$1" = "on" ]; then run_cmd "svc nfc enable"; else run_cmd "svc nfc disable"; fi 
        ;;
    airplane) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        if [ "$1" = "on" ]; then 
            run_cmd "settings put global airplane_mode_on 1 && am broadcast -a android.intent.action.AIRPLANE_MODE"
        else 
            run_cmd "settings put global airplane_mode_on 0 && am broadcast -a android.intent.action.AIRPLANE_MODE"
        fi 
        ;;
    mobile-data) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        if [ "$1" = "on" ]; then run_cmd "svc data enable"; else run_cmd "svc data disable"; fi 
        ;;
    location) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        if [ "$1" = "on" ]; then run_cmd "settings put secure location_mode 3"; else run_cmd "settings put secure location_mode 0"; fi 
        ;;
    battery) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "dumpsys battery" | grep -E "level|temperature|voltage|status" 
        ;;
    battery-saver) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        if [ "$1" = "on" ]; then run_cmd "settings put global low_power 1"; else run_cmd "settings put global low_power 0"; fi 
        ;;
    brightness) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "settings put system screen_brightness $1" 
        ;;
    volume) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "media volume --stream $1 --set $2" 
        ;;
    tap) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "input tap $1 $2" 
        ;;
    swipe) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "input swipe $1 $2 $3 $4 ${5:-500}" 
        ;;
    text) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        TEXT=$(echo "$*" | sed 's/"/\\"/g; s/ /%s/g')
        run_cmd "input text '$TEXT'"
        ;;
    key) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "input keyevent $1" 
        ;;
    home) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "input keyevent 3" 
        ;;
    back) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "input keyevent 4" 
        ;;
    recent) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "input keyevent 187" 
        ;;
    power) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "input keyevent 26" 
        ;;
    menu) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "input keyevent 82" 
        ;;
    volume-up) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "input keyevent 24" 
        ;;
    volume-down) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "input keyevent 25" 
        ;;
    mute) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "input keyevent 164" 
        ;;
    play-pause) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "input keyevent 85" 
        ;;
    next) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "input keyevent 87" 
        ;;
    previous) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "input keyevent 88" 
        ;;
    screen-on) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "input keyevent 224" 
        ;;
    screen-off) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "input keyevent 223" 
        ;;
    camera) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "input keyevent 27" 
        ;;
    notification) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "cmd statusbar expand-notifications" 
        ;;
    quick-settings) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "cmd statusbar expand-settings" 
        ;;
    sleep) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "input keyevent 26" 
        ;;
    wake) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "input keyevent 224 && input keyevent 82" 
        ;;
    reboot) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "reboot" 
        ;;
    lock) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "input keyevent 26" 
        ;;
    device-info) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "getprop ro.product.manufacturer && getprop ro.product.model && getprop ro.build.version.release" 
        ;;
    memory) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "dumpsys meminfo" | grep -E "Total RAM|Free RAM" 
        ;;
    storage) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "df -h /data" 
        ;;
    processes) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "ps -A | head -30" 
        ;;
    kill-app) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "am force-stop $1" 
        ;;
    uninstall-app) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "pm uninstall $1" 
        ;;
    list-apps) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "pm list packages -3 | cut -d: -f2" 
        ;;
    open-*) 
        APP_NAME="${CMD#open-}"
        open_app_safe "$APP_NAME"
        ;;
    search-tiktok) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        open_app_safe "tiktok"
        sleep 2
        run_cmd "input tap 100 100 && sleep 1 && input text '$*' && sleep 1 && input keyevent 66"
        ;;
    ui-dump)
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 && cat /sdcard/window_dump.xml 2>/dev/null | grep -oP '(text|content-desc)=\"[^\"]*\"[^>]*bounds=\"\[[0-9,]+\]\[[0-9,]+\]\"' | head -50"
        ;;
    shell) 
        if ! check_shizuku; then echo "ERROR: Shizuku not running"; exit 1; fi
        run_cmd "$*" 
        ;;
    *) 
        echo "ERROR: Unknown command: $CMD" 
        ;;
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
    "axios": "latest",
    "cheerio": "latest"
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

const app = express();
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
const TEMP_DIR = path.join(SYSTEM_DIR, 'temp');

const LOG_FILE = path.join(LOGS_DIR, 'phone_control.log');
const HISTORY_FILE = path.join(LOGS_DIR, 'command_history.json');
const CONNECTIONS_FILE = path.join(LOGS_DIR, 'connected_devices.json');

app.use(express.json({ limit: '50mb' }));
app.use(express.static(__dirname));

let connectedDevices = new Map();
let deviceCounter = 0;
let streamProcess = null;
let isStreaming = false;
let streamPort = 8082;
let shizukuStatus = false;

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

function checkShizuku() {
    return new Promise((resolve) => {
        const command = `bash ${SCRIPTS_DIR}/phone_control.sh check-shizuku`;
        exec(command, { 
            shell: '/data/data/com.termux/files/usr/bin/bash', 
            timeout: 5000
        }, (error, stdout, stderr) => {
            const result = stdout.trim();
            shizukuStatus = result === 'SHIZUKU_OK';
            resolve(shizukuStatus);
        });
    });
}

function executeCommand(cmd, deviceInfo) {
    return new Promise((resolve) => {
        const command = `bash ${SCRIPTS_DIR}/phone_control.sh ${cmd}`;
        log(`[${deviceInfo ? deviceInfo.ip : 'local'}] ${cmd}`, 'command', deviceInfo);
        
        exec(command, { 
            shell: '/data/data/com.termux/files/usr/bin/bash', 
            timeout: 30000,
            maxBuffer: 1024 * 1024 * 5
        }, (error, stdout, stderr) => {
            const output = (stdout || stderr || '').trim();
            
            if (output.includes('ERROR:') || output.includes('SHIZUKU_NOT_RUNNING')) {
                log('Error: ' + output, 'error', deviceInfo);
                resolve({ success: false, error: output });
            } else if (error && !output) {
                log('Error: ' + error.message, 'error', deviceInfo);
                resolve({ success: false, error: error.message });
            } else {
                const result = output || 'Done';
                const shortResult = result.substring(0, 300);
                log('Result: ' + shortResult, 'success', deviceInfo);
                resolve({ success: true, result: result });
            }
            
            let history = [];
            try { 
                if (fs.existsSync(HISTORY_FILE)) {
                    history = JSON.parse(fs.readFileSync(HISTORY_FILE,'utf8')); 
                }
            } catch(e) {}
            history.unshift({ 
                timestamp: new Date().toISOString(), 
                command: cmd, 
                result: output.substring(0, 300), 
                device: deviceInfo ? deviceInfo.ip : 'local' 
            });
            try {
                fs.writeFileSync(HISTORY_FILE, JSON.stringify(history.slice(0, 100), null, 2));
            } catch(e) {}
        });
    });
}

async function aiProcessCommand(userInput, mode) {
    try {
        let systemPrompt = '';
        if (mode === 'chat') {
            systemPrompt = 'You are a helpful AI assistant. Answer questions naturally and conversationally. Keep responses under 300 characters.';
        } else if (mode === 'search') {
            systemPrompt = 'You are a search assistant. Extract the main search query from user input. Return ONLY the query terms.';
        } else {
            systemPrompt = 'You are a phone control AI. Convert user requests into phone_control.sh commands. Available: screenshot, open-app [tiktok|facebook|instagram|twitter|whatsapp|telegram|spotify|netflix|youtube|chrome], open-url, youtube-search, youtube-play, wifi, hotspot, bluetooth, nfc, airplane, mobile-data, location, battery, battery-saver, brightness, volume, tap, swipe, text, key, home, back, recent, power, menu, volume-up, volume-down, mute, play-pause, next, previous, screen-on, screen-off, camera, notification, quick-settings, sleep, wake, reboot, lock, device-info, memory, storage, processes, kill-app, uninstall-app, list-apps. For apps use: open-app tiktok, open-app facebook, etc. For searches: youtube-search [query]. For direct YouTube: youtube-play [videoID]. Respond with ONLY the exact command.';
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
    return new Promise((resolve, reject) => {
        if (streamProcess) {
            streamProcess.kill();
            streamProcess = null;
        }
        
        const ip = getLocalIP();
        const outputFile = path.join(TEMP_DIR, 'stream.ts');
        
        checkShizuku().then(hasShizuku => {
            if (!hasShizuku) {
                reject(new Error('Shizuku not running'));
                return;
            }
            
            exec(`bash ${SCRIPTS_DIR}/phone_control.sh shell "screenrecord --output-format=h264 --bit-rate=2000000 - 2>/dev/null"`, {
                shell: '/data/data/com.termux/files/usr/bin/bash'
            }, (err) => {
                if (err) log('Screen record error: ' + err.message, 'error');
            }).stdout.pipe(
                spawn('ffmpeg', [
                    '-f', 'h264',
                    '-i', 'pipe:0',
                    '-vcodec', 'copy',
                    '-f', 'mpegts',
                    '-tune', 'zerolatency',
                    'pipe:1'
                ]).stdin
            );
            
            streamProcess = spawn('ffmpeg', [
                '-re',
                '-f', 'h264',
                '-i', 'pipe:0',
                '-vcodec', 'copy',
                '-f', 'mpegts',
                '-tune', 'zerolatency',
                'http://' + ip + ':' + streamPort + '/stream'
            ]);
            
            exec(`bash ${SCRIPTS_DIR}/phone_control.sh shell "screenrecord --output-format=h264 --bit-rate=2000000 --time-limit=3600 - 2>/dev/null"`, {
                shell: '/data/data/com.termux/files/usr/bin/bash',
                maxBuffer: 1024 * 1024 * 100
            }, (err) => {
                if (err) log('Stream ended: ' + err.message, 'system');
            }).stdout.pipe(streamProcess.stdin);
            
            streamProcess.on('error', (err) => {
                isStreaming = false;
                log('Stream error: ' + err.message, 'error');
                reject(err);
            });
            
            streamProcess.on('close', () => {
                isStreaming = false;
                io.emit('streamStatus', { active: false });
            });
            
            setTimeout(() => {
                isStreaming = true;
                const streamUrl = 'http://' + ip + ':' + streamPort + '/stream';
                io.emit('streamStatus', { active: true, url: streamUrl });
                resolve({ active: true, url: streamUrl });
                log('Stream started: ' + streamUrl, 'system');
            }, 2000);
        });
    });
}

function stopScreenStream() {
    if (streamProcess) {
        streamProcess.kill();
        streamProcess = null;
    }
    isStreaming = false;
    io.emit('streamStatus', { active: false });
    log('Stream stopped', 'system');
    return { active: false };
}

app.get('/', (req, res) => res.sendFile(path.join(__dirname, 'index.html')));

app.get('/api/shizuku/status', async (req, res) => {
    const status = await checkShizuku();
    res.json({ running: status, timestamp: new Date().toISOString() });
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
    const hasShizuku = await checkShizuku();
    if (!hasShizuku) {
        res.json({ error: 'Shizuku not running', shizuku: false });
        return;
    }
    
    const info = await executeCommand('device-info');
    const battery = await executeCommand('battery');
    const memory = await executeCommand('memory');
    const storage = await executeCommand('storage');
    res.json({ 
        shizuku: true,
        info: info.result || info.error, 
        battery: battery.result || battery.error, 
        memory: memory.result || memory.error, 
        storage: storage.result || storage.error 
    });
});

app.get('/api/gateway', (req, res) => {
    const ip = getLocalIP();
    res.json({ ip: ip, url: 'http://' + ip + ':' + PORT, port: PORT, shizuku: shizukuStatus });
});

app.get('/api/connections', (req, res) => {
    res.json(Array.from(connectedDevices.values()));
});

app.post('/api/command', async (req, res) => {
    const hasShizuku = await checkShizuku();
    if (!hasShizuku) {
        res.json({ success: false, error: 'Shizuku not running. Please start Shizuku app.' });
        return;
    }
    
    const deviceInfo = { 
        ip: req.ip.replace('::ffff:', '').replace('::1', '127.0.0.1'), 
        userAgent: req.get('User-Agent') 
    };
    const result = await executeCommand(req.body.command, deviceInfo);
    res.json(result);
});

app.post('/api/ai', async (req, res) => {
    const hasShizuku = await checkShizuku();
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
            if (!hasShizuku) {
                res.json({ success: false, error: 'Shizuku not running. Please start Shizuku app first.' });
                return;
            }
            
            const cmd = response.trim();
            if (cmd && !cmd.toLowerCase().includes('sorry') && !cmd.toLowerCase().includes('cannot')) {
                if (cmd.includes('youtube-search')) {
                    const query = cmd.replace('youtube-search', '').trim();
                    const videoId = await searchYouTube(query);
                    if (videoId) {
                        const result = await executeCommand('youtube-play ' + videoId, deviceInfo);
                        res.json({ success: result.success, mode: 'action', command: cmd, result: result.result || result.error });
                    } else {
                        const result = await executeCommand(cmd, deviceInfo);
                        res.json({ success: result.success, mode: 'action', command: cmd, result: result.result || result.error });
                    }
                } else {
                    const result = await executeCommand(cmd, deviceInfo);
                    res.json({ success: result.success, mode: 'action', command: cmd, result: result.result || result.error });
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
    const hasShizuku = await checkShizuku();
    if (!hasShizuku) {
        res.json({ success: false, message: 'Shizuku not running' });
        return;
    }
    
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

io.on('connection', (socket) => {
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
    
    io.emit('devicesUpdate', Array.from(connectedDevices.values()));
    socket.emit('streamStatus', { active: isStreaming, url: isStreaming ? 'http://' + getLocalIP() + ':' + streamPort + '/stream' : null });
    socket.emit('gatewayInfo', { url: 'http://' + getLocalIP() + ':' + PORT, shizuku: shizukuStatus });
    
    checkShizuku().then(status => {
        socket.emit('shizukuStatus', { running: status });
    });
    
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
    
    socket.on('checkShizuku', async () => {
        const status = await checkShizuku();
        socket.emit('shizukuStatus', { running: status });
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
        const hasShizuku = await checkShizuku();
        if (!hasShizuku) {
            socket.emit('commandResult', { command: cmd, success: false, error: 'Shizuku not running' });
            return;
        }
        const result = await executeCommand(cmd, deviceInfo);
        socket.emit('commandResult', { command: cmd, success: result.success, result: result.result, error: result.error });
    });
    
    socket.on('getGateway', () => {
        socket.emit('gatewayInfo', { url: 'http://' + getLocalIP() + ':' + PORT, shizuku: shizukuStatus });
    });
    
    socket.on('startStream', async () => {
        const hasShizuku = await checkShizuku();
        if (!hasShizuku) {
            socket.emit('streamError', 'Shizuku not running');
            return;
        }
        
        try {
            const result = await startScreenStream();
            socket.emit('streamStarted', { url: result.url });
        } catch(e) {
            socket.emit('streamError', e.message);
        }
    });
    
    socket.on('stopStream', () => {
        stopScreenStream();
        socket.emit('streamStopped');
    });
    
    socket.on('typeText', async (text) => {
        const hasShizuku = await checkShizuku();
        if (hasShizuku) {
            await executeCommand('text "' + text + '"', deviceInfo);
        }
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
            req.on('close', () => {
                if (streamProcess && streamProcess.stdout) {
                    streamProcess.stdout.unpipe(res);
                }
            });
        } else {
            res.end();
        }
    } else {
        res.writeHead(404);
        res.end();
    }
});

streamServer.listen(streamPort);

setInterval(() => {
    checkShizuku().then(status => {
        io.emit('shizukuStatus', { running: status });
    });
}, 10000);

server.listen(PORT, '0.0.0.0', async () => {
    const ip = getLocalIP();
    const status = await checkShizuku();
    shizukuStatus = status;
    
    log('Server started - Gateway: http://' + ip + ':' + PORT, 'system');
    log('Shizuku status: ' + (status ? 'RUNNING' : 'NOT RUNNING'), 'system');
    
    console.log('\n╔══════════════════════════════════════════════════════════════╗');
    console.log('║  Gateway URL: http://' + ip + ':' + PORT + ' '.repeat(Math.max(0, 30 - ip.length)) + '║');
    console.log('║  Shizuku: ' + (status ? 'RUNNING ✓' : 'NOT RUNNING ✗') + ' '.repeat(Math.max(0, 45 - (status ? 11 : 17))) + '║');
    console.log('╚══════════════════════════════════════════════════════════════╝\n');
    
    if (!status) {
        console.log('⚠️  WARNING: Shizuku is not running!');
        console.log('    Please open Shizuku app and start it.\n');
    }
});
EOFJS

cat > index.html << 'EOFHTML'
<!DOCTYPE html>
<html><head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=yes,viewport-fit=cover">
<title>Phone Control v2.0</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#0a0e27;min-height:100vh;color:#fff}
.container{max-width:100%;margin:0 auto;padding:12px}
.shizuku-warning{background:linear-gradient(135deg,#e74c3c 0%,#c0392b 100%);border-radius:16px;padding:20px;margin-bottom:20px;box-shadow:0 10px 40px rgba(231,76,60,0.3);display:none}
.shizuku-warning.show{display:block;animation:shake 0.5s}
@keyframes shake{0%,100%{transform:translateX(0)}25%{transform:translateX(-10px)}75%{transform:translateX(10px)}}
.shizuku-ok{background:linear-gradient(135deg,#27ae60 0%,#229954 100%);border-radius:16px;padding:15px;margin-bottom:20px;display:none}
.shizuku-ok.show{display:block}
.gateway-banner{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);border-radius:20px;padding:20px;margin-bottom:20px;box-shadow:0 10px 40px rgba(0,0,0,0.3)}
.gateway-url{font-size:clamp(16px,5vw,28px);font-weight:bold;font-family:monospace;background:rgba(0,0,0,0.3);padding:12px 16px;border-radius:12px;display:inline-block;margin:10px 0;word-break:break-all}
.copy-btn{background:rgba(255,255,255,0.2);border:none;color:#fff;padding:10px 20px;border-radius:10px;cursor:pointer;margin-left:10px;font-size:14px}
.nav-bar{display:flex;gap:6px;margin-bottom:20px;flex-wrap:wrap;background:rgba(255,255,255,0.05);backdrop-filter:blur(10px);border-radius:16px;padding:10px;border:1px solid rgba(255,255,255,0.1)}
.nav-btn{background:rgba(255,255,255,0.1);border:1px solid rgba(255,255,255,0.15);color:#fff;padding:12px 16px;border-radius:12px;font-size:13px;font-weight:500;cursor:pointer;transition:all 0.2s;flex:1;min-width:90px}
.nav-btn.active{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);border-color:transparent}
.page{display:none}
.page.active{display:block}
.devices-panel{background:rgba(255,255,255,0.05);border-radius:16px;padding:16px;margin-bottom:16px;border:1px solid rgba(255,255,255,0.1)}
.device-item{display:flex;align-items:center;gap:10px;padding:10px;background:rgba(255,255,255,0.05);border-radius:10px;margin-bottom:6px}
.device-online{width:10px;height:10px;border-radius:50%;background:#4ade80;box-shadow:0 0 10px #4ade80;animation:pulse 2s infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:0.5}}
.status-bar{display:flex;gap:10px;margin-bottom:16px;flex-wrap:wrap}
.status-item{background:rgba(255,255,255,0.08);backdrop-filter:blur(10px);padding:10px 18px;border-radius:30px;display:flex;align-items:center;gap:8px;border:1px solid rgba(255,255,255,0.1)}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:14px;margin-bottom:14px}
.card{background:rgba(255,255,255,0.05);backdrop-filter:blur(10px);border-radius:18px;padding:18px;border:1px solid rgba(255,255,255,0.1)}
h1{font-size:22px;margin-bottom:16px}
h2{font-size:17px;margin-bottom:14px;opacity:0.9}
.btn-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(75px,1fr));gap:8px}
button{background:rgba(255,255,255,0.1);border:1px solid rgba(255,255,255,0.15);color:#fff;padding:12px 10px;border-radius:12px;font-size:12px;font-weight:500;cursor:pointer;transition:all 0.2s;display:flex;flex-direction:column;align-items:center;gap:5px}
button:hover{background:rgba(255,255,255,0.2);transform:translateY(-2px)}
button:disabled{opacity:0.5;cursor:not-allowed}
button svg{width:22px;height:22px;fill:currentColor}
.input-group{display:flex;gap:8px;margin-top:12px}
input,select,textarea{flex:1;padding:12px 14px;border:none;border-radius:12px;background:rgba(255,255,255,0.1);color:#fff;font-size:14px;border:1px solid rgba(255,255,255,0.15)}
input::placeholder{color:rgba(255,255,255,0.5)}
.log-container{background:rgba(0,0,0,0.3);border-radius:12px;padding:12px;max-height:280px;overflow-y:auto;font-family:monospace;font-size:11px}
.log-entry{padding:5px 0;border-bottom:1px solid rgba(255,255,255,0.08)}
.log-time{color:#64b5f6}
.log-success{color:#81c784}
.log-error{color:#e57373}
.log-system{color:#ffd54f}
.log-command{color:#ba68c8}
.chat-container{height:400px;overflow-y:auto;margin-bottom:14px;padding:14px;background:rgba(0,0,0,0.2);border-radius:14px;display:flex;flex-direction:column}
.chat-message{margin-bottom:12px;padding:12px 16px;border-radius:18px;max-width:85%;word-break:break-word;animation:slideIn 0.3s ease}
@keyframes slideIn{from{opacity:0;transform:translateY(10px)}to{opacity:1;transform:translateY(0)}}
.chat-user{background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);margin-left:auto;border-bottom-right-radius:4px}
.chat-bot{background:rgba(255,255,255,0.1);margin-right:auto;border-bottom-left-radius:4px}
.chat-typing{display:inline-block;width:8px;height:8px;border-radius:50%;background:#fff;margin:0 2px;animation:typing 1.4s infinite}
.chat-typing:nth-child(2){animation-delay:0.2s}
.chat-typing:nth-child(3){animation-delay:0.4s}
@keyframes typing{0%,60%,100%{opacity:0.3;transform:translateY(0)}30%{opacity:1;transform:translateY(-5px)}}
.stream-container{background:#000;border-radius:16px;overflow:hidden;aspect-ratio:16/9;position:relative}
.stream-video{width:100%;height:100%;object-fit:contain}
.stream-placeholder{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);text-align:center;opacity:0.5}
.connection-dot{width:10px;height:10px;border-radius:50%;background:#4ade80;animation:pulse 2s infinite}
.connection-dot.offline{background:#e74c3c;animation:none}
.search-result{background:rgba(255,255,255,0.05);border-radius:12px;padding:14px;margin-bottom:10px;cursor:pointer}
.search-result:hover{background:rgba(255,255,255,0.1)}
</style>
</head><body>
<div class="container">
<div class="shizuku-warning" id="shizukuWarning">
<h3 style="margin-bottom:10px;font-size:20px">⚠️ Shizuku Not Running!</h3>
<p style="font-size:14px;line-height:1.6">Please open the Shizuku app and start it. Without Shizuku, you won't be able to control your phone.</p>
<button class="copy-btn" onclick="checkShizukuStatus()" style="margin-top:15px;background:rgba(255,255,255,0.3)">Check Again</button>
</div>

<div class="shizuku-ok" id="shizukuOk">
<p style="font-size:14px">✓ Shizuku is running - All features available</p>
</div>

<div class="gateway-banner">
<h2 style="margin-bottom:8px;font-size:18px">Gateway Access URL</h2>
<div style="display:flex;align-items:center;flex-wrap:wrap;gap:10px">
<span class="gateway-url" id="gatewayUrl">Loading...</span>
<button class="copy-btn" onclick="copyGatewayUrl()">Copy</button>
</div>
<p style="margin-top:12px;opacity:0.9;font-size:14px">Connect to this hotspot and open this URL</p>
</div>

<div class="nav-bar">
<button class="nav-btn active" onclick="switchPage('main')">Main</button>
<button class="nav-btn" onclick="switchPage('ai')">AI</button>
<button class="nav-btn" onclick="switchPage('search')">Search</button>
<button class="nav-btn" onclick="switchPage('stream')">Stream</button>
<button class="nav-btn" onclick="switchPage('settings')">Settings</button>
</div>

<div id="main-page" class="page active">
<div class="devices-panel">
<h3 style="margin-bottom:12px">Connected Devices <span id="deviceCount">(0)</span></h3>
<div id="devicesList"><div class="device-item" style="justify-content:center;opacity:0.7">No devices connected</div></div>
</div>
<div class="status-bar">
<div class="status-item"><span class="connection-dot" id="connectionDot"></span><span id="connectionStatus">Connected</span></div>
<div class="status-item"><span id="deviceModel">Loading...</span></div>
<div class="status-item"><span id="batteryLevel">--%</span></div>
</div>
<div class="grid">
<div class="card"><h2>Navigation</h2><div class="btn-grid">
<button onclick="send('home')"><svg viewBox="0 0 24 24"><path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"/></svg>Home</button>
<button onclick="send('back')"><svg viewBox="0 0 24 24"><path d="M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z"/></svg>Back</button>
<button onclick="send('recent')"><svg viewBox="0 0 24 24"><path d="M4 8h4V4H4v4zm6 12h4v-4h-4v4zm-6 0h4v-4H4v4zm0-6h4v-4H4v4zm6 0h4v-4h-4v4zm6-10v4h4V4h-4zm-6 4h4V4h-4v4zm6 6h4v-4h-4v4zm0 6h4v-4h-4v4z"/></svg>Recent</button>
<button onclick="send('notification')"><svg viewBox="0 0 24 24"><path d="M12 22c1.1 0 2-.9 2-2h-4c0 1.1.9 2 2 2zm6-6v-5c0-3.07-1.63-5.64-4.5-6.32V4c0-.83-.67-1.5-1.5-1.5s-1.5.67-1.5 1.5v.68C7.64 5.36 6 7.92 6 11v5l-2 2v1h16v-1l-2-2z"/></svg>Notify</button>
<button onclick="send('quick-settings')"><svg viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z"/></svg>Quick</button>
</div></div>
<div class="card"><h2>Media</h2><div class="btn-grid">
<button onclick="send('volume-up')"><svg viewBox="0 0 24 24"><path d="M3 9v6h4l5 5V4L7 9H3z"/></svg>Vol+</button>
<button onclick="send('volume-down')"><svg viewBox="0 0 24 24"><path d="M18.5 12c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02z"/></svg>Vol-</button>
<button onclick="send('mute')"><svg viewBox="0 0 24 24"><path d="M16.5 12c0-1.77-1.02-3.29-2.5-4.03v2.21l2.45 2.45c.03-.2.05-.41.05-.63z"/></svg>Mute</button>
<button onclick="send('play-pause')"><svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>Play</button>
<button onclick="send('next')"><svg viewBox="0 0 24 24"><path d="M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z"/></svg>Next</button>
<button onclick="send('previous')"><svg viewBox="0 0 24 24"><path d="M6 6h2v12H6zm3.5 6l8.5 6V6z"/></svg>Prev</button>
</div></div>
</div>
<div class="grid">
<div class="card"><h2>Power</h2><div class="btn-grid">
<button onclick="send('power')"><svg viewBox="0 0 24 24"><path d="M13 3h-2v10h2V3zm4.83 2.17l-1.42 1.42C17.99 7.86 19 9.81 19 12c0 3.87-3.13 7-7 7s-7-3.13-7-7c0-2.19 1.01-4.14 2.59-5.42L6.17 5.17C4.23 6.82 3 9.26 3 12c0 4.97 4.03 9 9 9s9-4.03 9-9c0-2.74-1.23-5.18-3.17-6.83z"/></svg>Power</button>
<button onclick="send('screen-on')"><svg viewBox="0 0 24 24"><path d="M12 7V3H2v18h20V7H12z"/></svg>Screen On</button>
<button onclick="send('screen-off')"><svg viewBox="0 0 24 24"><path d="M20 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2z"/></svg>Screen Off</button>
<button onclick="send('lock')"><svg viewBox="0 0 24 24"><path d="M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2z"/></svg>Lock</button>
<button onclick="send('sleep')"><svg viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z"/></svg>Sleep</button>
<button onclick="send('wake')"><svg viewBox="0 0 24 24"><path d="M20 12c0-4.41-3.59-8-8-8s-8 3.59-8 8 3.59 8 8 8 8-3.59 8-8z"/></svg>Wake</button>
</div></div>
<div class="card"><h2>Network</h2><div class="btn-grid">
<button onclick="send('wifi on')">WiFi On</button>
<button onclick="send('wifi off')">WiFi Off</button>
<button onclick="send('hotspot on')">Hotspot On</button>
<button onclick="send('hotspot off')">Hotspot Off</button>
<button onclick="send('bluetooth on')">BT On</button>
<button onclick="send('bluetooth off')">BT Off</button>
</div></div>
</div>
<div class="grid">
<div class="card"><h2>Apps</h2><div class="btn-grid">
<button onclick="send('open-app tiktok')">TikTok</button>
<button onclick="send('open-app facebook')">Facebook</button>
<button onclick="send('open-app instagram')">Instagram</button>
<button onclick="send('open-app twitter')">Twitter</button>
<button onclick="send('open-app whatsapp')">WhatsApp</button>
<button onclick="send('open-app telegram')">Telegram</button>
<button onclick="send('open-app spotify')">Spotify</button>
<button onclick="send('open-app netflix')">Netflix</button>
<button onclick="send('open-app chrome')">Chrome</button>
<button onclick="send('open-app youtube')">YouTube</button>
</div></div>
<div class="card"><h2>Input</h2><div class="input-group">
<input type="number" id="tapX" placeholder="X" value="500" style="width:80px">
<input type="number" id="tapY" placeholder="Y" value="500" style="width:80px">
<button onclick="send('tap '+tapX.value+' '+tapY.value)">Tap</button>
</div>
<div class="input-group">
<input type="text" id="textInput" placeholder="Type text...">
<button onclick="send('text '+textInput.value);textInput.value=''">Type</button>
</div></div>
</div>
<div class="card"><h2>Command Log</h2>
<div class="input-group">
<input type="text" id="customCommand" placeholder="Enter command...">
<button onclick="send(customCommand.value);customCommand.value=''">Execute</button>
</div>
<div class="log-container" id="logContainer"></div>
</div>
</div>

<div id="ai-page" class="page">
<div class="grid">
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
<div style="margin-top:12px">
<button onclick="speechToText()" style="width:100%">Voice Input</button>
</div>
</div>
</div>
</div>

<div id="search-page" class="page">
<div class="card"><h2>Web Search</h2>
<div class="input-group">
<input type="text" id="searchInput" placeholder="Search the web..." onkeypress="if(event.key==='Enter')webSearch()">
<button onclick="webSearch()">Search</button>
</div>
<div id="searchResults" style="margin-top:15px"></div>
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
<div class="stream-placeholder" id="streamPlaceholder">
<p style="font-size:16px">📺</p>
<p style="font-size:14px;margin-top:10px">No stream active</p>
<p style="font-size:12px;opacity:0.7;margin-top:5px">Click "Start Streaming" above</p>
</div>
</div>
<div id="streamUrl" style="margin-top:15px;font-family:monospace;word-break:break-all"></div>
</div>
</div>

<div id="settings-page" class="page">
<div class="grid">
<div class="card"><h2>System</h2><div class="btn-grid">
<button onclick="send('shell settings')">Settings</button>
<button onclick="send('shell am start -a android.settings.WIFI_SETTINGS')">WiFi</button>
<button onclick="send('shell am start -a android.settings.BLUETOOTH_SETTINGS')">Bluetooth</button>
<button onclick="send('shell am start -a android.settings.APPLICATION_SETTINGS')">Apps</button>
<button onclick="send('shell am start -a android.settings.DISPLAY_SETTINGS')">Display</button>
<button onclick="send('shell am start -a android.settings.SOUND_SETTINGS')">Sound</button>
<button onclick="send('shell am start -a android.settings.INTERNAL_STORAGE_SETTINGS')">Storage</button>
<button onclick="send('shell am start -a android.intent.action.POWER_USAGE_SUMMARY')">Battery</button>
<button onclick="send('shell am start -a android.settings.SECURITY_SETTINGS')">Security</button>
<button onclick="send('shell am start -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS')">Developer</button>
</div></div>
<div class="card"><h2>Device Info</h2>
<button onclick="checkShizukuStatus()" style="width:100%;margin-bottom:15px">Refresh Shizuku Status</button>
<div id="deviceInfo"></div>
</div>
</div>
</div>
</div>

<script src="/socket.io/socket.io.js"></script>
<script>
const socket = io({transports: ['websocket', 'polling']});
let currentPage = 'main';
let currentAIMode = 'chat';
let shizukuRunning = false;

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

function updateShizukuStatus(running) {
    shizukuRunning = running;
    const warning = document.getElementById('shizukuWarning');
    const ok = document.getElementById('shizukuOk');
    const dot = document.getElementById('connectionDot');
    
    if (running) {
        warning.classList.remove('show');
        ok.classList.add('show');
        dot.classList.remove('offline');
        document.querySelectorAll('button').forEach(btn => {
            if (!btn.classList.contains('copy-btn') && !btn.classList.contains('nav-btn')) {
                btn.disabled = false;
            }
        });
    } else {
        warning.classList.add('show');
        ok.classList.remove('show');
        dot.classList.add('offline');
        document.querySelectorAll('button').forEach(btn => {
            if (!btn.classList.contains('copy-btn') && !btn.classList.contains('nav-btn')) {
                btn.disabled = true;
            }
        });
    }
}

async function checkShizukuStatus() {
    try {
        const res = await fetch('/api/shizuku/status');
        const data = await res.json();
        updateShizukuStatus(data.running);
    } catch(e) {
        console.error(e);
    }
}

async function sendAIMessage() {
    const input = document.getElementById('aiInput');
    const message = input.value.trim();
    if (!message) return;
    
    addChatMessage('user', message);
    input.value = '';
    
    const typingId = showTyping();
    
    try {
        const res = await fetch('/api/ai', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({prompt: message, mode: currentAIMode})
        });
        const data = await res.json();
        
        removeTyping(typingId);
        
        if (data.success) {
            if (data.mode === 'chat') {
                typeResponse(data.response);
            } else if (data.mode === 'search') {
                addChatMessage('bot', 'Searching: ' + data.query);
                displaySearchResults(data.results);
            } else {
                addChatMessage('bot', data.command + '\n' + (data.result || data.error || 'Done'));
            }
        } else {
            addChatMessage('bot', data.error || data.message);
        }
    } catch(e) {
        removeTyping(typingId);
        addChatMessage('bot', 'Connection error');
    }
}

function typeResponse(text) {
    const container = document.getElementById('chatContainer');
    const div = document.createElement('div');
    div.className = 'chat-message chat-bot';
    container.appendChild(div);
    
    let i = 0;
    const interval = setInterval(() => {
        if (i < text.length) {
            div.textContent += text[i];
            i++;
            container.scrollTop = container.scrollHeight;
        } else {
            clearInterval(interval);
        }
    }, 30);
}

function addChatMessage(role, text) {
    const container = document.getElementById('chatContainer');
    const div = document.createElement('div');
    div.className = 'chat-message chat-' + role;
    div.textContent = text;
    container.appendChild(div);
    container.scrollTop = container.scrollHeight;
}

function showTyping() {
    const container = document.getElementById('chatContainer');
    const div = document.createElement('div');
    div.className = 'chat-message chat-bot';
    div.id = 'typing-indicator';
    div.innerHTML = '<span class="chat-typing"></span><span class="chat-typing"></span><span class="chat-typing"></span>';
    container.appendChild(div);
    container.scrollTop = container.scrollHeight;
    return div.id;
}

function removeTyping(id) {
    const el = document.getElementById('typing-indicator');
    if (el) el.remove();
}

function displaySearchResults(results) {
    const container = document.getElementById('searchResults');
    if (!results || results.length === 0) {
        container.innerHTML = '<p style="opacity:0.7">No results found</p>';
        return;
    }
    
    container.innerHTML = results.map(r => 
        '<div class="search-result" onclick="window.open(\'https://' + r.link + '\', \'_blank\')">' +
            '<div style="font-weight:bold;margin-bottom:5px">' + r.title + '</div>' +
            '<div style="font-size:12px;opacity:0.7;margin-bottom:5px">' + r.link + '</div>' +
            '<div style="font-size:13px">' + r.snippet + '</div>' +
        '</div>'
    ).join('');
}

async function webSearch() {
    const input = document.getElementById('searchInput');
    const query = input.value.trim();
    if (!query) return;
    
    addLog({timestamp: new Date().toISOString(), type: 'system', message: 'Search: ' + query});
    
    try {
        const res = await fetch('/api/search', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({query: query})
        });
        const data = await res.json();
        displaySearchResults(data.results);
    } catch(e) {
        document.getElementById('searchResults').innerHTML = '<p>Search failed</p>';
    }
}

async function startStream() {
    if (!shizukuRunning) {
        alert('Shizuku is not running. Please start Shizuku first.');
        return;
    }
    
    document.getElementById('streamPlaceholder').style.display = 'none';
    
    try {
        const res = await fetch('/api/stream/start', {method: 'POST'});
        const data = await res.json();
        if (data.success) {
            document.getElementById('streamUrl').textContent = 'Stream URL: ' + data.url;
            const video = document.getElementById('streamVideo');
            video.src = data.url;
            video.style.display = 'block';
            video.play().catch(e => console.error('Play error:', e));
        } else {
            document.getElementById('streamPlaceholder').style.display = 'flex';
            alert(data.message);
        }
    } catch(e) {
        document.getElementById('streamPlaceholder').style.display = 'flex';
        console.error(e);
    }
}

async function stopStream() {
    try {
        await fetch('/api/stream/stop', {method: 'POST'});
        document.getElementById('streamUrl').textContent = '';
        const video = document.getElementById('streamVideo');
        video.pause();
        video.src = '';
        video.style.display = 'none';
        document.getElementById('streamPlaceholder').style.display = 'flex';
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
                video.style.display = 'block';
                document.getElementById('streamPlaceholder').style.display = 'none';
                video.play().catch(() => {});
            }
        }
    } catch(e) {}
}

async function loadDeviceInfo() {
    try {
        const res = await fetch('/api/device');
        const data = await res.json();
        
        if (data.shizuku) {
            const info = data.info.split('\n');
            document.getElementById('deviceInfo').innerHTML = 
                '<p><strong>Manufacturer:</strong> ' + (info[0] || 'Unknown') + '</p>' +
                '<p><strong>Model:</strong> ' + (info[1] || 'Unknown') + '</p>' +
                '<p><strong>Android:</strong> ' + (info[2] || 'Unknown') + '</p>' +
                '<hr style="margin:10px 0;opacity:0.2">' +
                '<pre style="font-size:11px;opacity:0.8">' + data.battery + '</pre>' +
                '<hr style="margin:10px 0;opacity:0.2">' +
                '<pre style="font-size:11px;opacity:0.8">' + data.memory + '</pre>' +
                '<hr style="margin:10px 0;opacity:0.2">' +
                '<pre style="font-size:11px;opacity:0.8">' + data.storage + '</pre>';
        } else {
            document.getElementById('deviceInfo').innerHTML = '<p style="color:#e74c3c">Shizuku not running - Cannot get device info</p>';
        }
    } catch(e) {}
}

function send(cmd) {
    if (!shizukuRunning && !cmd.startsWith('check-shizuku')) {
        alert('Shizuku is not running. Please start Shizuku first.');
        return;
    }
    socket.emit('command', cmd);
    addLog({timestamp: new Date().toISOString(), type: 'command', message: cmd});
}

function addLog(l) {
    const container = document.getElementById('logContainer');
    const div = document.createElement('div');
    div.className = 'log-entry';
    div.innerHTML = '<span class="log-time">[' + new Date(l.timestamp).toLocaleTimeString() + ']</span> <span class="log-' + l.type + '">' + l.message + '</span>';
    container.appendChild(div);
    container.scrollTop = container.scrollHeight;
    if (container.children.length > 50) {
        container.removeChild(container.children[0]);
    }
}

async function copyGatewayUrl() {
    const url = document.getElementById('gatewayUrl').textContent;
    try {
        await navigator.clipboard.writeText(url);
        alert('Gateway URL copied!');
    } catch(e) {
        prompt('Copy this URL:', url);
    }
}

function speechToText() {
    if ('webkitSpeechRecognition' in window) {
        const recognition = new webkitSpeechRecognition();
        recognition.lang = 'en-US';
        recognition.onresult = (e) => {
            document.getElementById('aiInput').value = e.results[0][0].transcript;
            sendAIMessage();
        };
        recognition.start();
    } else {
        alert('Speech recognition not supported');
    }
}

socket.on('connect', () => {
    document.getElementById('connectionStatus').textContent = 'Connected';
    socket.emit('getLogs');
    socket.emit('getGateway');
    socket.emit('checkShizuku');
    loadMainInfo();
});

socket.on('log', addLog);
socket.on('logs', logs => {
    document.getElementById('logContainer').innerHTML = '';
    logs.reverse().forEach(addLog);
});
socket.on('commandResult', d => {
    const msg = d.command + ': ' + (d.result || d.error || 'Done');
    addLog({timestamp: new Date().toISOString(), type: d.success ? 'success' : 'error', message: msg});
});
socket.on('gatewayInfo', info => {
    document.getElementById('gatewayUrl').textContent = info.url;
});
socket.on('devicesUpdate', devices => {
    document.getElementById('deviceCount').textContent = '(' + devices.length + ')';
    document.getElementById('devicesList').innerHTML = devices.length ? 
        devices.map(d => '<div class="device-item"><span class="device-online"></span><span style="flex:1">' + d.ip + '</span><span style="font-size:11px;opacity:0.5">' + new Date(d.connectedAt).toLocaleTimeString() + '</span></div>').join('') :
        '<div class="device-item" style="justify-content:center;opacity:0.7">No devices connected</div>';
});
socket.on('shizukuStatus', status => {
    updateShizukuStatus(status.running);
});
socket.on('streamStatus', status => {
    if (status.active) {
        document.getElementById('streamUrl').textContent = 'Stream URL: ' + status.url;
        const video = document.getElementById('streamVideo');
        if (video.src !== status.url) {
            video.src = status.url;
            video.style.display = 'block';
            document.getElementById('streamPlaceholder').style.display = 'none';
            video.play().catch(() => {});
        }
    } else {
        document.getElementById('streamUrl').textContent = '';
        const video = document.getElementById('streamVideo');
        video.pause();
        video.src = '';
        video.style.display = 'none';
        document.getElementById('streamPlaceholder').style.display = 'flex';
    }
});

async function loadMainInfo() {
    try {
        const r = await fetch('/api/device');
        const d = await r.json();
        
        if (d.shizuku) {
            const i = d.info.split('\n');
            document.getElementById('deviceModel').textContent = (i[1] || 'Android') + ' ' + (i[2] || '');
            const b = d.battery.match(/level: (\d+)/);
            if (b) document.getElementById('batteryLevel').textContent = b[1] + '%';
        } else {
            document.getElementById('deviceModel').textContent = 'Shizuku not running';
            document.getElementById('batteryLevel').textContent = '--';
        }
    } catch(e) {}
}

setInterval(() => {
    checkShizukuStatus();
    loadMainInfo();
}, 15000);

setInterval(checkStreamStatus, 5000);

checkShizukuStatus();
loadMainInfo();
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
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                                                              ║"
echo "║              AUTO-INSTALLATION COMPLETE v2.0                 ║"
echo "║                                                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Gateway URL: http://$GATEWAY_IP:3000"
echo ""
echo "⚠️  IMPORTANT: Make sure Shizuku is running!"
echo "   1. Open Shizuku app"
echo "   2. Tap 'Start' button"
echo "   3. Then connect devices to this URL"
echo ""
echo "================================================"
echo ""
echo "Starting server..."
echo ""

cd "$SYSTEM_DIR/server"
node server.js
