#!/data/data/com.termux/files/usr/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
export LANG=C
export LC_ALL=C

clear
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "                    PHONE GATEWAY CONTROLLER v4.0"
echo "                 Shizuku | AI Agent | Hotspot Ready"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

pkill -f "node.*gateway" 2>/dev/null || true
pkill -f "http-server" 2>/dev/null || true

echo "[1/8] Installing system packages..."
pkg update -y 2>&1 | grep -E "(Reading|Building)" || true
pkg install -y nodejs python git curl jq termux-api net-tools 2>&1 | grep -E "(Setting up|Unpacking)" || true
pip install requests 2>/dev/null || true
echo ""

echo "[2/8] Creating project structure..."
rm -rf ~/phonegate 2>/dev/null || true
mkdir -p ~/phonegate/{web,data,scripts}
cd ~/phonegate
echo ""

echo "[3/8] Setting up Shizuku integration..."
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
bash ~/phonegate/shizuku_setup.sh
echo ""

echo "[4/8] Creating phone controller..."
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
    agent) python3 ~/phonegate/scripts/phone_agent.py "$2" ;;
    *) echo "Unknown: $1" ;;
esac
CONTROL
chmod +x ~/phonegate/control.sh
echo ""

echo "[5/8] Creating AI Phone Agent..."
cat > ~/phonegate/scripts/phone_agent.py << 'AGENT'
#!/data/data/com.termux/files/usr/bin/python3
import subprocess, base64, json, sys, time, os, re
from urllib.request import Request, urlopen
MODEL = "gemini-2.5-flash-lite"
MAX_STEPS = 25
SCREENSHOT_PATH = "/sdcard/agent_screen.png"
TELEGRAM_BOT_TOKEN = ""
TELEGRAM_CHAT_ID = ""
SEND_TELEGRAM_UPDATES = False

def load_api_key():
    config_path = os.path.expanduser("~/.phonegate/config.json")
    try:
        with open(config_path) as f:
            data = json.load(f)
            return data.get("gemini_api_key", "")
    except:
        pass
    return os.environ.get("GEMINI_API_KEY", "")

def run_cmd(cmd):
    try:
        result = subprocess.run(["rish", "-c", cmd], capture_output=True, text=True, timeout=15)
        return result.stdout.strip()
    except:
        return ""

def take_screenshot():
    run_cmd(f"screencap -p {SCREENSHOT_PATH}")
    time.sleep(0.3)
    with open(SCREENSHOT_PATH, "rb") as f:
        return base64.b64encode(f.read()).decode()

def get_ui_elements():
    run_cmd("uiautomator dump /sdcard/ui.xml")
    time.sleep(0.5)
    xml = run_cmd("cat /sdcard/ui.xml")
    if not xml: return []
    elements = []
    pattern = r'<node[^>]*?text="(?P<text>[^"]*)"[^>]*?resource-id="(?P<rid>[^"]*)"[^>]*?class="(?P<cls>[^"]*)"[^>]*?content-desc="(?P<desc>[^"]*)"[^>]*?clickable="(?P<click>[^"]*)"[^>]*?bounds="\[(?P<x1>\d+),(?P<y1>\d+)\]\[(?P<x2>\d+),(?P<y2>\d+)\]"'
    for m in re.finditer(pattern, xml):
        text = m.group("text") or m.group("desc")
        rid = m.group("rid")
        clickable = m.group("click") == "true"
        x1, y1 = int(m.group("x1")), int(m.group("y1"))
        x2, y2 = int(m.group("x2")), int(m.group("y2"))
        cx, cy = (x1 + x2) // 2, (y1 + y2) // 2
        if text or (clickable and rid):
            elements.append({"label": text, "clickable": clickable, "center": [cx, cy], "bounds": [x1, y1, x2, y2], "type": m.group("cls").split(".")[-1]})
    return elements

def execute_action(action):
    atype = action.get("action", "")
    if atype == "tap": run_cmd(f"input tap {int(action['x'])} {int(action['y'])}")
    elif atype == "swipe": run_cmd(f"input swipe {int(action['x1'])} {int(action['y1'])} {int(action['x2'])} {int(action['y2'])} {int(action.get('duration', 300))}")
    elif atype == "type":
        text = action.get("text", "").replace(" ", "%s").replace("'", "\\'")
        run_cmd(f"input text '{text}'")
    elif atype == "key": run_cmd(f"input keyevent {int(action.get('code', 0))}")
    elif atype == "open_app": run_cmd(f"monkey -p {action.get('package', '')} 1")
    elif atype == "wait": time.sleep(float(action.get("seconds", 1)))
    elif atype == "scroll_down": run_cmd("input swipe 540 1600 540 600 300")
    elif atype == "scroll_up": run_cmd("input swipe 540 600 540 1600 300")
    elif atype == "go_home": run_cmd("input keyevent 3")
    elif atype == "go_back": run_cmd("input keyevent 4")
    elif atype == "done": return "done"
    return "continue"

SYSTEM_PROMPT = """You are an Android phone agent. Output JSON with "thought" and "actions" array.
Available actions: tap (x,y), swipe (x1,y1,x2,y2,duration), type (text), key (code:3=HOME,4=BACK,66=ENTER), open_app (package), wait (seconds), scroll_down, scroll_up, go_home, go_back, done (message).
Common packages: com.whatsapp, com.instagram.android, com.google.android.youtube, com.android.chrome.
Screen: 1080x2240. Status bar y<80, center (540,1120), nav bar y>2000."""

def call_gemini(api_key, parts):
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent?key={api_key}"
    payload = {"systemInstruction": {"parts": [{"text": SYSTEM_PROMPT}]}, "contents": [{"parts": parts}], "generationConfig": {"temperature": 0.2, "maxOutputTokens": 1024, "responseMimeType": "application/json"}}
    req = Request(url, data=json.dumps(payload).encode(), method="POST")
    req.add_header("Content-Type", "application/json")
    with urlopen(req, timeout=60) as r:
        text = json.loads(r.read())["candidates"][0]["content"]["parts"][0]["text"]
    if text.startswith("```"): text = re.sub(r'^```\w*\n?', '', text); text = re.sub(r'\n?```$', '', text)
    return json.loads(text)

def main():
    global TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, SEND_TELEGRAM_UPDATES
    config_path = os.path.expanduser("~/.phonegate/config.json")
    if os.path.exists(config_path):
        with open(config_path) as f:
            cfg = json.load(f)
            TELEGRAM_BOT_TOKEN = cfg.get("telegram_bot_token", "")
            TELEGRAM_CHAT_ID = cfg.get("telegram_chat_id", "")
            SEND_TELEGRAM_UPDATES = cfg.get("telegram_enabled", False)
    
    args = sys.argv[1:]
    if "--notify" in args:
        SEND_TELEGRAM_UPDATES = True
        args.remove("--notify")
    if not args:
        print("Usage: python3 phone_agent.py [--notify] \"<task>\"")
        return
    
    task = " ".join(args)
    api_key = load_api_key()
    if not api_key:
        print("ERROR: No API key. Configure in Settings.")
        return
    
    print(f"Agent starting: {task}")
    parts = []
    for step in range(1, MAX_STEPS + 1):
        print(f"Step {step}/{MAX_STEPS}")
        b64 = take_screenshot()
        ui_elements = get_ui_elements()
        ui_text = "\n".join([f"[{i}] {e['label']} ({e['center'][0]},{e['center'][1]})" for i, e in enumerate(ui_elements[:30])])
        msg = f"TASK: {task}\nStep {step}\nUI Elements:\n{ui_text}"
        parts = [{"inline_data": {"mimeType": "image/png", "data": b64}}, {"text": msg}]
        resp = call_gemini(api_key, parts)
        print(f"Thought: {resp.get('thought', '')}")
        for action in resp.get("actions", []):
            if execute_action(action) == "done":
                print(f"Done: {action.get('message', 'Complete')}")
                return
            time.sleep(0.5)
        time.sleep(1)
    print("Max steps reached")

if __name__ == "__main__":
    main()
AGENT
chmod +x ~/phonegate/scripts/phone_agent.py
echo ""

echo "[6/8] Creating gateway server..."
cat > ~/phonegate/server.js << 'SERVER'
const http = require('http');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

const PORT = process.env.PORT || 3000;
const controlScript = path.join(__dirname, 'control.sh');
const connections = new Map();
let requestCount = 0;

const mimeTypes = {'.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.json': 'application/json', '.svg': 'image/svg+xml'};

function getLocalIP() {
    return new Promise((resolve) => {
        exec("ip addr show wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1", (e1, ip1) => {
            if (ip1 && ip1.trim()) return resolve(ip1.trim());
            exec("ip addr show ap0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1", (e2, ip2) => {
                if (ip2 && ip2.trim()) return resolve(ip2.trim());
                exec("ip route get 1 2>/dev/null | grep -oP 'src \\K\\S+'", (e3, ip3) => {
                    resolve(ip3 && ip3.trim() ? ip3.trim() : '192.168.43.1');
                });
            });
        });
    });
}

function logConnection(ip, msg) {
    const time = new Date().toLocaleTimeString();
    console.log(`[${time}] ${ip} - ${msg}`);
}

function execCommand(cmd, args = '') {
    return new Promise((resolve) => {
        exec(`bash ${controlScript} ${cmd} ${args}`, { timeout: 15000 }, (err, stdout, stderr) => {
            resolve(err ? `Error: ${err.message}` : (stdout || stderr || 'Done'));
        });
    });
}

const server = http.createServer(async (req, res) => {
    const clientIP = (req.headers['x-forwarded-for'] || req.connection.remoteAddress || 'unknown').replace('::ffff:', '');
    requestCount++;
    
    if (!connections.has(clientIP)) {
        connections.set(clientIP, { firstSeen: new Date(), requests: 0 });
        logConnection(clientIP, 'NEW CONNECTION');
    }
    connections.get(clientIP).requests++;
    
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
            try {
                const { cmd, args } = JSON.parse(body);
                logConnection(clientIP, `Command: ${cmd} ${args || ''}`);
                const result = await execCommand(cmd, args);
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ result }));
            } catch (e) {
                res.writeHead(400);
                res.end(JSON.stringify({ error: 'Invalid request' }));
            }
        });
        return;
    }
    
    if (url.pathname === '/api/config') {
        if (req.method === 'GET') {
            const configPath = path.join(require('os').homedir(), '.phonegate/config.json');
            if (fs.existsSync(configPath)) {
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(fs.readFileSync(configPath));
            } else {
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ gemini_api_key: '', telegram_bot_token: '', telegram_chat_id: '', telegram_enabled: false }));
            }
        } else if (req.method === 'POST') {
            let body = '';
            req.on('data', chunk => body += chunk);
            req.on('end', () => {
                const configDir = path.join(require('os').homedir(), '.phonegate');
                if (!fs.existsSync(configDir)) fs.mkdirSync(configDir, { recursive: true });
                fs.writeFileSync(path.join(configDir, 'config.json'), body);
                res.writeHead(200);
                res.end(JSON.stringify({ saved: true }));
            });
        }
        return;
    }
    
    if (url.pathname === '/api/commands') {
        const commands = ['tap', 'swipe', 'text', 'key', 'home', 'back', 'recent', 'power', 'volup', 'voldown', 'screenshot', 'openapp', 'openurl', 'battery', 'brightness', 'volume', 'wifi_on', 'wifi_off', 'bluetooth_on', 'bluetooth_off', 'location_on', 'location_off', 'flashlight_on', 'flashlight_off', 'notify', 'vibrate', 'clipboard', 'applist', 'info', 'ui', 'shell', 'agent'];
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ commands }));
        return;
    }
    
    let filePath = path.join(__dirname, 'web', url.pathname === '/' ? 'index.html' : url.pathname);
    fs.readFile(filePath, (err, content) => {
        if (err) {
            res.writeHead(404);
            res.end('Not Found');
        } else {
            res.writeHead(200, { 'Content-Type': mimeTypes[path.extname(filePath)] || 'text/plain' });
            res.end(content);
        }
    });
});

server.listen(PORT, '0.0.0.0', async () => {
    const ip = await getLocalIP();
    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('PHONE GATEWAY ONLINE');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log(`Gateway URL: http://${ip}:${PORT}`);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('\nWaiting for connections...\n');
});

setInterval(() => {
    if (connections.size > 0) {
        console.log(`\nActive: ${connections.size} | Requests: ${requestCount}`);
        connections.forEach((d, ip) => console.log(`  ${ip}: ${d.requests} requests`));
        console.log('');
    }
}, 30000);
SERVER
echo ""

echo "[7/8] Creating web interface with SVG icons..."
cat > ~/phonegate/web/index.html << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=yes">
    <title>Phone Gateway</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(145deg, #0f0c29 0%, #302b63 50%, #24243e 100%);
            min-height: 100vh;
            padding: 16px;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        
        nav {
            display: flex;
            gap: 8px;
            margin-bottom: 20px;
            flex-wrap: wrap;
        }
        .nav-btn {
            background: rgba(255,255,255,0.1);
            border: 1px solid rgba(255,255,255,0.2);
            color: white;
            padding: 12px 20px;
            border-radius: 50px;
            cursor: pointer;
            font-size: 14px;
            font-weight: 500;
            display: flex;
            align-items: center;
            gap: 8px;
            transition: all 0.2s;
            backdrop-filter: blur(10px);
        }
        .nav-btn svg { width: 20px; height: 20px; fill: currentColor; }
        .nav-btn.active { background: #6366f1; border-color: #818cf8; }
        .nav-btn:hover { background: rgba(255,255,255,0.2); }
        
        .page { display: none; }
        .page.active { display: block; }
        
        .header {
            background: rgba(255,255,255,0.08);
            backdrop-filter: blur(20px);
            padding: 20px 24px;
            border-radius: 24px;
            margin-bottom: 20px;
            border: 1px solid rgba(255,255,255,0.1);
        }
        .header h1 {
            font-size: clamp(1.5rem, 5vw, 2.2rem);
            background: linear-gradient(135deg, #a78bfa, #c4b5fd);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            margin-bottom: 8px;
        }
        .header p { color: #a1a1aa; }
        
        .status-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 12px;
            margin-bottom: 20px;
        }
        .status-card {
            background: rgba(255,255,255,0.08);
            backdrop-filter: blur(20px);
            padding: 18px;
            border-radius: 18px;
            border: 1px solid rgba(255,255,255,0.1);
        }
        .status-card h3 {
            color: #a1a1aa;
            font-size: 13px;
            font-weight: 500;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-bottom: 8px;
        }
        .status-card p {
            color: white;
            font-size: 1.4rem;
            font-weight: 600;
        }
        .status-card .online { color: #4ade80; }
        .status-card .offline { color: #f87171; }
        
        .panel {
            background: rgba(255,255,255,0.08);
            backdrop-filter: blur(20px);
            padding: 24px;
            border-radius: 24px;
            border: 1px solid rgba(255,255,255,0.1);
            margin-bottom: 20px;
        }
        .panel h2 {
            color: white;
            font-size: 1.2rem;
            margin-bottom: 20px;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .panel h2 svg { width: 24px; height: 24px; fill: #a78bfa; }
        
        .btn-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(100px, 1fr));
            gap: 10px;
        }
        .btn {
            background: rgba(255,255,255,0.1);
            border: 1px solid rgba(255,255,255,0.15);
            color: white;
            padding: 14px 12px;
            border-radius: 14px;
            cursor: pointer;
            font-size: 13px;
            font-weight: 500;
            display: flex;
            flex-direction: column;
            align-items: center;
            gap: 8px;
            transition: all 0.2s;
        }
        .btn svg { width: 24px; height: 24px; fill: #a78bfa; }
        .btn:hover { background: #6366f1; border-color: #818cf8; }
        .btn:hover svg { fill: white; }
        
        .input-row {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            margin-bottom: 16px;
        }
        .input-row input, .input-row textarea {
            flex: 1;
            min-width: 150px;
            padding: 14px 18px;
            background: rgba(0,0,0,0.3);
            border: 1px solid rgba(255,255,255,0.2);
            border-radius: 14px;
            color: white;
            font-size: 14px;
        }
        .input-row input::placeholder { color: #71717a; }
        .input-row button {
            padding: 14px 28px;
            background: #6366f1;
            border: none;
            border-radius: 14px;
            color: white;
            font-weight: 600;
            cursor: pointer;
        }
        
        .config-section {
            margin-bottom: 24px;
        }
        .config-section label {
            display: block;
            color: #a1a1aa;
            margin-bottom: 8px;
            font-size: 14px;
        }
        .config-section input {
            width: 100%;
            padding: 14px 18px;
            background: rgba(0,0,0,0.3);
            border: 1px solid rgba(255,255,255,0.2);
            border-radius: 14px;
            color: white;
            font-size: 14px;
            margin-bottom: 16px;
        }
        
        .output-console {
            background: #0a0a0f;
            border-radius: 16px;
            padding: 20px;
            color: #4ade80;
            font-family: 'Monaco', 'Menlo', monospace;
            font-size: 13px;
            min-height: 200px;
            max-height: 400px;
            overflow-y: auto;
            white-space: pre-wrap;
            border: 1px solid rgba(255,255,255,0.1);
        }
        
        .toast {
            position: fixed;
            bottom: 24px;
            right: 24px;
            background: #1e1b4b;
            color: white;
            padding: 14px 24px;
            border-radius: 50px;
            font-weight: 500;
            animation: slide 0.3s;
            z-index: 1000;
            border: 1px solid #6366f1;
        }
        @keyframes slide { from { opacity: 0; transform: translateX(20px); } to { opacity: 1; transform: translateX(0); } }
        
        @media (max-width: 600px) {
            body { padding: 10px; }
            .panel { padding: 18px; }
            .btn-grid { grid-template-columns: repeat(3, 1fr); }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Phone Gateway</h1>
            <p>Remote control with AI agent support</p>
        </div>
        
        <nav>
            <button class="nav-btn active" data-page="control">
                <svg viewBox="0 0 24 24"><path d="M4 6h16v2H4V6zm0 5h16v2H4v-2zm0 5h10v2H4v-2z"/></svg>
                Control
            </button>
            <button class="nav-btn" data-page="agent">
                <svg viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/></svg>
                AI Agent
            </button>
            <button class="nav-btn" data-page="settings">
                <svg viewBox="0 0 24 24"><path d="M19.14 12.94c.04-.3.06-.61.06-.94 0-.33-.02-.64-.06-.94l2.02-1.58c.18-.14.23-.38.12-.56l-1.89-3.28c-.12-.19-.36-.26-.56-.18l-2.38.96c-.5-.38-1.06-.68-1.66-.88L14.45 3.5c-.04-.2-.2-.34-.4-.34h-3.78c-.2 0-.36.14-.4.34l-.3 2.52c-.6.2-1.16.5-1.66.88l-2.38-.96c-.2-.08-.44-.01-.56.18l-1.89 3.28c-.11.18-.06.42.12.56l2.02 1.58c-.04.3-.06.61-.06.94 0 .33.02.64.06.94l-2.02 1.58c-.18.14-.23.38-.12.56l1.89 3.28c.12.19.36.26.56.18l2.38-.96c.5.38 1.06.68 1.66.88l.3 2.52c.04.2.2.34.4.34h3.78c.2 0 .36-.14.4-.34l.3-2.52c.6-.2 1.16-.5 1.66-.88l2.38.96c.2.08.44.01.56-.18l1.89-3.28c.11-.18.06-.42-.12-.56l-2.02-1.58zM12 15c-1.66 0-3-1.34-3-3s1.34-3 3-3 3 1.34 3 3-1.34 3-3 3z"/></svg>
                Settings
            </button>
        </nav>
        
        <div class="status-grid">
            <div class="status-card"><h3>Status</h3><p id="connStatus" class="online">Online</p></div>
            <div class="status-card"><h3>Device</h3><p id="deviceInfo">Loading...</p></div>
            <div class="status-card"><h3>Battery</h3><p id="batteryLevel">--%</p></div>
        </div>
        
        <div id="controlPage" class="page active">
            <div class="panel">
                <h2><svg viewBox="0 0 24 24"><path d="M3 13h8V3H3v10zm0 8h8v-6H3v6zm10 0h8V11h-8v10zm0-18v6h8V3h-8z"/></svg>Quick Actions</h2>
                <div class="btn-grid">
                    <button class="btn" onclick="execCmd('home')"><svg viewBox="0 0 24 24"><path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"/></svg>Home</button>
                    <button class="btn" onclick="execCmd('back')"><svg viewBox="0 0 24 24"><path d="M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z"/></svg>Back</button>
                    <button class="btn" onclick="execCmd('recent')"><svg viewBox="0 0 24 24"><path d="M3 6h18v2H3V6zm0 5h18v2H3v-2zm0 5h18v2H3v-2z"/></svg>Recent</button>
                    <button class="btn" onclick="execCmd('power')"><svg viewBox="0 0 24 24"><path d="M13 3h-2v10h2V3zm4.83 2.17l-1.42 1.42C17.99 7.86 19 9.81 19 12c0 3.87-3.13 7-7 7s-7-3.13-7-7c0-2.19 1.01-4.14 2.59-5.42L6.17 5.17C4.23 6.82 3 9.26 3 12c0 4.97 4.03 9 9 9s9-4.03 9-9c0-2.74-1.23-5.18-3.17-6.83z"/></svg>Power</button>
                    <button class="btn" onclick="execCmd('volup')"><svg viewBox="0 0 24 24"><path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02z"/></svg>Vol+</button>
                    <button class="btn" onclick="execCmd('voldown')"><svg viewBox="0 0 24 24"><path d="M18.5 12c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM5 9v6h4l5 5V4L9 9H5z"/></svg>Vol-</button>
                    <button class="btn" onclick="execCmd('screenshot')"><svg viewBox="0 0 24 24"><path d="M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2zM8.5 13.5l2.5 3.01L14.5 12l4.5 6H5l3.5-4.5z"/></svg>Screen</button>
                    <button class="btn" onclick="execCmd('wifi_on')"><svg viewBox="0 0 24 24"><path d="M1 9l2 2c4.97-4.97 13.03-4.97 18 0l2-2C16.03 2.97 7.97 2.97 1 9zm8 8l3 3 3-3c-1.66-1.66-4.34-1.66-6 0zm-4-4l2 2c2.76-2.76 7.24-2.76 10 0l2-2C15.07 9.07 8.93 9.07 5 13z"/></svg>WiFi ON</button>
                    <button class="btn" onclick="execCmd('flashlight_on')"><svg viewBox="0 0 24 24"><path d="M20 4h-4L9 2 2 6v12l7 4 7-2h4c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2z"/></svg>Flash</button>
                </div>
            </div>
            
            <div class="panel">
                <h2><svg viewBox="0 0 24 24"><path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-7 14H6v-2h6v2zm3-4H6v-2h9v2zm3-4H6V7h12v2z"/></svg>Custom Commands</h2>
                <div class="input-row">
                    <input type="text" id="tapX" placeholder="X coord">
                    <input type="text" id="tapY" placeholder="Y coord">
                    <button onclick="execTap()">Tap</button>
                </div>
                <div class="input-row">
                    <input type="text" id="textInput" placeholder="Text to type...">
                    <button onclick="execText()">Type</button>
                </div>
                <div class="input-row">
                    <input type="text" id="urlInput" placeholder="URL or app package...">
                    <button onclick="execUrl()">Open</button>
                </div>
                <div class="input-row">
                    <input type="text" id="shellInput" placeholder="Custom shell command...">
                    <button onclick="execShell()">Execute</button>
                </div>
            </div>
        </div>
        
        <div id="agentPage" class="page">
            <div class="panel">
                <h2><svg viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/></svg>AI Phone Agent</h2>
                <p style="color:#a1a1aa; margin-bottom:20px;">Describe what you want the agent to do</p>
                <div class="input-row">
                    <input type="text" id="agentTask" placeholder="e.g., Open YouTube and search for music" style="flex:3;">
                    <button onclick="runAgent()">Run Agent</button>
                </div>
                <label style="display:flex; align-items:center; gap:10px; color:#a1a1aa; margin-top:12px;">
                    <input type="checkbox" id="telegramNotify"> Send progress to Telegram
                </label>
            </div>
        </div>
        
        <div id="settingsPage" class="page">
            <div class="panel">
                <h2><svg viewBox="0 0 24 24"><path d="M19.14 12.94c.04-.3.06-.61.06-.94 0-.33-.02-.64-.06-.94l2.02-1.58c.18-.14.23-.38.12-.56l-1.89-3.28c-.12-.19-.36-.26-.56-.18l-2.38.96c-.5-.38-1.06-.68-1.66-.88L14.45 3.5c-.04-.2-.2-.34-.4-.34h-3.78c-.2 0-.36.14-.4.34l-.3 2.52c-.6.2-1.16.5-1.66.88l-2.38-.96c-.2-.08-.44-.01-.56.18l-1.89 3.28c-.11.18-.06.42.12.56l2.02 1.58c-.04.3-.06.61-.06.94 0 .33.02.64.06.94l-2.02 1.58c-.18.14-.23.38-.12.56l1.89 3.28c.12.19.36.26.56.18l2.38-.96c.5.38 1.06.68 1.66.88l.3 2.52c.04.2.2.34.4.34h3.78c.2 0 .36-.14.4-.34l.3-2.52c.6-.2 1.16-.5 1.66-.88l2.38.96c.2.08.44.01.56-.18l1.89-3.28c.11-.18.06-.42-.12-.56l-2.02-1.58zM12 15c-1.66 0-3-1.34-3-3s1.34-3 3-3 3 1.34 3 3-1.34 3-3 3z"/></svg>Configuration</h2>
                <div class="config-section">
                    <label>Gemini API Key</label>
                    <input type="password" id="geminiKey" placeholder="AIza...">
                </div>
                <div class="config-section">
                    <label>Telegram Bot Token</label>
                    <input type="password" id="telegramToken" placeholder="123456:ABC...">
                </div>
                <div class="config-section">
                    <label>Telegram Chat ID</label>
                    <input type="text" id="telegramChatId" placeholder="123456789">
                </div>
                <button class="btn" style="width:100%; padding:16px;" onclick="saveConfig()">Save Configuration</button>
            </div>
        </div>
        
        <div class="panel">
            <h2><svg viewBox="0 0 24 24"><path d="M20 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm0 14H4V6h16v12z"/></svg>Console Output</h2>
            <div class="output-console" id="console">Ready...</div>
        </div>
    </div>
    
    <script>
        const consoleEl = document.getElementById('console');
        let currentConfig = {};
        
        function log(msg) { consoleEl.textContent = msg + '\\n' + consoleEl.textContent; }
        function toast(msg) {
            const t = document.createElement('div'); t.className = 'toast'; t.textContent = msg;
            document.body.appendChild(t); setTimeout(() => t.remove(), 3000);
        }
        
        async function execCmd(cmd, args = '') {
            try {
                const res = await fetch('/api/command', {
                    method: 'POST', headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({cmd, args})
                });
                const data = await res.json();
                log(`> ${cmd} ${args}\\n${data.result}`);
                toast(`${cmd} executed`);
            } catch(e) { log(`Error: ${e.message}`); }
        }
        
        function execTap() {
            const x = document.getElementById('tapX').value, y = document.getElementById('tapY').value;
            if(x && y) execCmd('tap', `${x} ${y}`);
        }
        function execText() {
            const t = document.getElementById('textInput').value;
            if(t) execCmd('text', t);
        }
        function execUrl() {
            const u = document.getElementById('urlInput').value;
            if(u) execCmd(u.includes('://') ? 'openurl' : 'openapp', u);
        }
        function execShell() {
            const s = document.getElementById('shellInput').value;
            if(s) execCmd('shell', `"${s}"`);
        }
        
        async function runAgent() {
            const task = document.getElementById('agentTask').value;
            const notify = document.getElementById('telegramNotify').checked;
            if(!task) return;
            log(`Starting AI Agent: ${task}`);
            let cmd = `agent "${task}"`;
            if(notify) cmd = `agent --notify "${task}"`;
            execCmd('shell', `"python3 ~/phonegate/scripts/phone_agent.py ${notify ? '--notify ' : ''}\\${task}\\""`);
        }
        
        async function loadStatus() {
            try {
                const res = await fetch('/api/status');
                const data = await res.json();
                document.getElementById('connStatus').className = 'online';
                document.getElementById('connStatus').textContent = 'Online';
                const info = data.info.split('\\n');
                document.getElementById('deviceInfo').textContent = info[0] || 'Android';
                const level = data.battery.match(/level: (\\d+)/);
                document.getElementById('batteryLevel').textContent = level ? level[1] + '%' : '--';
            } catch(e) {
                document.getElementById('connStatus').className = 'offline';
                document.getElementById('connStatus').textContent = 'Offline';
            }
        }
        
        async function loadConfig() {
            try {
                const res = await fetch('/api/config');
                currentConfig = await res.json();
                document.getElementById('geminiKey').value = currentConfig.gemini_api_key || '';
                document.getElementById('telegramToken').value = currentConfig.telegram_bot_token || '';
                document.getElementById('telegramChatId').value = currentConfig.telegram_chat_id || '';
            } catch(e) {}
        }
        
        async function saveConfig() {
            const config = {
                gemini_api_key: document.getElementById('geminiKey').value,
                telegram_bot_token: document.getElementById('telegramToken').value,
                telegram_chat_id: document.getElementById('telegramChatId').value,
                telegram_enabled: true
            };
            await fetch('/api/config', {
                method: 'POST',
                body: JSON.stringify(config)
            });
            toast('Configuration saved');
        }
        
        document.querySelectorAll('.nav-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                document.querySelectorAll('.nav-btn').forEach(b => b.classList.remove('active'));
                document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
                btn.classList.add('active');
                document.getElementById(btn.dataset.page + 'Page').classList.add('active');
            });
        });
        
        loadStatus(); loadConfig();
        setInterval(loadStatus, 5000);
    </script>
</body>
</html>
HTML
echo ""

echo "[8/8] Creating start script..."
cat > ~/phonegate/start.sh << 'START'
#!/data/data/com.termux/files/usr/bin/bash
cd ~/phonegate
echo ""
echo "Detecting network..."
IP=$(ip addr show wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
[ -z "$IP" ] && IP=$(ip addr show ap0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
[ -z "$IP" ] && IP=$(ip route get 1 2>/dev/null | grep -oP 'src \K\S+')
[ -z "$IP" ] && IP="192.168.43.1"
echo "Gateway URL: http://${IP}:3000"
echo ""
mkdir -p ~/.phonegate
node server.js
START
chmod +x ~/phonegate/start.sh

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "                             INSTALLATION COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "SETUP STEPS:"
echo ""
echo "1. Export Shizuku files:"
echo "   • Open Shizuku app"
echo "   • Tap 'Use Shizuku in terminal apps' → 'Export files'"
echo ""
echo "2. Start gateway:"
echo "   cd ~/phonegate && ./start.sh"
echo ""
echo "3. Configure in Web UI:"
echo "   • Open Settings tab"
echo "   • Add Gemini API key"
echo "   • Add Telegram bot token (optional)"
echo ""
echo "4. Connect other devices to hotspot and open the URL"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
