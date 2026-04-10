#!/data/data/com.termux/files/usr/bin/bash
pkg update -y
pkg install -y python rust binutils make clang wget curl termux-api
pip install --no-deps flask flask-socketio pillow mss numpy opencv-python pyautogui aiohttp websockets
mkdir -p ~/remote_server
cat > ~/remote_server/server.py << 'EOF'
import os,subprocess,socket,json,base64,time,io,threading
from flask import Flask,render_template_string
from flask_socketio import SocketIO,emit
from PIL import Image
import mss,numpy,pyautogui
warnings.filterwarnings("ignore")
app=Flask(__name__)
sio=SocketIO(app,cors_allowed_origins="*",async_mode='threading')
pyautogui.FAILSAFE=False
HTML='''<!DOCTYPE html><html><head><title>Remote</title><meta name="viewport" content="width=device-width,initial-scale=1"><style>*{margin:0;padding:0;box-sizing:border-box}body{background:#000;font-family:monospace;color:#0f0}#screen{width:100%;max-width:100%;cursor:crosshair;border:2px solid #0f0}#controls{padding:10px;background:#111;display:flex;flex-wrap:wrap;gap:5px}button{padding:10px;background:#1a1a1a;color:#0f0;border:1px solid #0f0}button:hover{background:#0f0;color:#000}input{padding:10px;background:#1a1a1a;color:#0f0;border:1px solid #0f0;flex:1}#out{background:#000;padding:10px;height:150px;overflow-y:scroll;font-size:11px;white-space:pre-wrap}.cmd{display:flex;gap:5px;margin-top:5px}</style></head><body><div id="stat">Ready</div><img id="screen" draggable="false"><div id="controls"><button onclick="sk('home')">HOME</button><button onclick="sk('back')">BACK</button><button onclick="sk('app_switch')">RECENTS</button><button onclick="sk('volume_up')">VOL+</button><button onclick="sk('volume_down')">VOL-</button><button onclick="sk('power')">POWER</button></div><div id="out"></div><div class="cmd"><input id="cmd" value="ls /sdcard"><button onclick="sc()">Run</button></div><script src="https://cdn.socket.io/4.5.0/socket.io.min.js"></script><script>const s=io(),scr=document.getElementById('screen'),stat=document.getElementById('stat'),out=document.getElementById('out');let sw=1080,sh=2400;s.on('connect',()=>stat.innerText='Connected');s.on('frame',d=>scr.src='data:image/jpeg;base64,'+d);s.on('out',d=>out.innerText=d);s.on('size',d=>{sw=d.w;sh=d.h});scr.onmousedown=e=>{let r=scr.getBoundingClientRect();s.emit('t',{a:'down',x:Math.round((e.clientX-r.left)*sw/r.width),y:Math.round((e.clientY-r.top)*sh/r.height)})};scr.onmouseup=e=>{let r=scr.getBoundingClientRect();s.emit('t',{a:'up',x:Math.round((e.clientX-r.left)*sw/r.width),y:Math.round((e.clientY-r.top)*sh/r.height)})};scr.onmousemove=e=>{if(e.buttons!==1)return;let r=scr.getBoundingClientRect();s.emit('t',{a:'move',x:Math.round((e.clientX-r.left)*sw/r.width),y:Math.round((e.clientY-r.top)*sh/r.height)})};scr.oncontextmenu=e=>e.preventDefault();function sk(k){s.emit('k',k)}function sc(){s.emit('c',document.getElementById('cmd').value)}document.getElementById('cmd').onkeypress=e=>{if(e.key==='Enter')sc()}</script></body></html>'''
def shrun(c):
 try:
  p=subprocess.run(['/storage/emulated/0/Shizuku/shizuku','shell',c],capture_output=True,text=True,timeout=10)
  return p.stdout+p.stderr
 except:
  try:
   p=subprocess.run(c,shell=True,capture_output=True,text=True,timeout=10,executable='/data/data/com.termux/files/usr/bin/bash')
   return p.stdout+p.stderr
  except Exception as e:return str(e)
def cap():
 try:
  with mss.mss() as s:
   i=s.grab(s.monitors[1])
   p=Image.frombytes('RGB',i.size,i.bgra,'raw','BGRX')
   p=p.resize((int(p.width*0.4),int(p.height*0.4)),Image.LANCZOS)
   b=io.BytesIO()
   p.save(b,format='JPEG',quality=30)
   return base64.b64encode(b.getvalue()).decode()
 except:return ''
def sz():
 try:
  with mss.mss() as s:return s.monitors[1]['width'],s.monitors[1]['height']
 except:return 1080,2400
@sio.on('connect')
def con():
 w,h=sz()
 emit('size',{'w':w,'h':h})
@sio.on('t')
def tch(d):
 a=d['a']
 if a=='move':a='MOVE'
 c=f"input motionevent {a} {d['x']} {d['y']}" if a=='MOVE' else f"input tap {d['x']} {d['y']}"
 shrun(c)
@sio.on('k')
def key(d):
 m={'home':'KEYCODE_HOME','back':'KEYCODE_BACK','app_switch':'KEYCODE_APP_SWITCH','volume_up':'KEYCODE_VOLUME_UP','volume_down':'KEYCODE_VOLUME_DOWN','power':'KEYCODE_POWER'}
 shrun(f"input keyevent {m.get(d,d)}")
@sio.on('c')
def cmd(d):
 r=shrun(d)
 emit('out',r)
def loop():
 while True:
  if sio.server.manager.rooms.get('/',{}):
   f=cap()
   if f:sio.emit('frame',f)
  time.sleep(0.08)
@app.route('/')
def idx():return render_template_string(HTML)
if __name__=='__main__':
 sio.start_background_task(loop)
 sio.run(app,host='0.0.0.0',port=5000,allow_unsafe_werkzeug=True)
EOF

cat > ~/remote_server/start.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
cd ~/remote_server
IP=$(ip route get 1 2>/dev/null | awk '{print $NF;exit}' || ifconfig wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}')
[ -z "$IP" ] && IP="127.0.0.1"
echo "http://$IP:5000"
python server.py
EOF
chmod +x ~/remote_server/start.sh
IP=$(ip route get 1 2>/dev/null | awk '{print $NF;exit}' || ifconfig wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}')
[ -z "$IP" ] && IP="127.0.0.1"
echo "======================================"
echo "REMOTE ACCESS READY"
echo "======================================"
echo "Gateway: $IP:5000"
echo "Run: ~/remote_server/start.sh"
echo "======================================"
