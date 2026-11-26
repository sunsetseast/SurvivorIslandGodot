import base64,secrets,threading,json,functools
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
from pathlib import Path
from playwright.sync_api import sync_playwright
import argparse
parser=argparse.ArgumentParser(description="Focused private Phase 4C mobile regression; authenticated loopback only.")
parser.add_argument('--build',type=Path,default=Path(__file__).resolve().parents[2]/'build/tonsai')
parser.add_argument('--captures',type=Path,default=Path(__file__).resolve().parents[2]/'build/phase4c-captures')
args=parser.parse_args()
args.captures.mkdir(parents=True,exist_ok=True)
password=secrets.token_urlsafe(32)
expected='Basic '+base64.b64encode(('review:'+password).encode()).decode()
class Handler(SimpleHTTPRequestHandler):
 def do_GET(self):
  if self.headers.get('Authorization')!=expected:
   self.send_response(401);self.send_header('WWW-Authenticate','Basic realm="Private QA"');self.end_headers();return
  super().do_GET()
 def log_message(self,*args):pass
server=ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Handler,directory=str(args.build.resolve())))
threading.Thread(target=server.serve_forever,daemon=True).start()

with sync_playwright() as p:
 browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader'])
 context=browser.new_context(viewport={'width':956,'height':440},has_touch=True,is_mobile=True,device_scale_factor=1,http_credentials={'username':'review','password':password})
 page=context.new_page();page.on('console',lambda m:print('BROWSER',m.text,flush=True) if m.type=='error' else None);errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 page.goto(f'http://127.0.0.1:{server.server_port}/?review')
 def state():return page.evaluate('JSON.parse(window.survivorApp)')
 def wait(expr):
  print('WAIT',expr,flush=True)
  page.wait_for_function('()=>window.survivorApp && ('+expr+')',timeout=90000)
 def tap(key):
  print("TAP",key,flush=True)
  page.wait_for_function("key=>window.survivorApp && JSON.parse(window.survivorApp).actions[key]",arg=key,timeout=90000)
  for attempt in range(20):
   x,y=state()['actions'][key]
   if 0<x<1 and 0<y<1:
    page.touchscreen.tap(x*956,y*440);page.wait_for_timeout(1200);return
   # Touch swipe the existing scrolling menu, no keyboard or popup input.
   client=context.new_cdp_session(page)
   for kind,ypos in [('touchStart',350),('touchMove',250),('touchMove',150),('touchEnd',150)]:
    client.send('Input.dispatchTouchEvent',{'type':kind,'touchPoints':[] if kind=='touchEnd' else [{'x':740,'y':ypos}]})
   client.detach();page.wait_for_timeout(300)
   page.screenshot(path=args.captures/'scroll.png')
  raise Exception(('unreachable',key,state()))
 wait('JSON.parse(window.survivorApp).screen === "MAIN"')
 tap('new');wait('JSON.parse(window.survivorApp).screen === "SELECTION"')
 tap('select');tap('standard');tap('Three Tribes')
 page.screenshot(path=args.captures/'setup.png')
 tap('confirm');tap('slot1');wait('JSON.parse(window.survivorApp).screen === "SESSION"')
 s=state();assert len(s['cast'])==6 and s['controlled']!='explorer',s
 page.screenshot(path=args.captures/'camp-six.png')
 tap('save');tap('menu');tap('continue');wait('JSON.parse(window.survivorApp).screen === "SESSION"')
 assert state()['controlled']==s['controlled']
 tap('menu');page.reload();wait('JSON.parse(window.survivorApp).screen === "MAIN"');tap('load');tap('slot1');wait('JSON.parse(window.survivorApp).screen === "SESSION"')
 assert state()['controlled']==s['controlled']
 tap('menu');tap('new');tap('select');tap('standard');tap('Two Tribes');tap('confirm');tap('slot2');wait('JSON.parse(window.survivorApp).screen === "SESSION"')
 assert len(state()['cast'])==9
 page.screenshot(path=args.captures/'camp-nine.png')
 tap('save');tap('menu');page.reload();wait('JSON.parse(window.survivorApp).screen === "MAIN"');tap('continue');wait('JSON.parse(window.survivorApp).screen === "SESSION"');assert len(state()['cast'])==9
 assert not errors,errors
 print('Mobile touch regression passed: setup, 6/9 rigs, Save/Continue/Exit/Reload/Load Game')
 browser.close()
server.shutdown()
