from playwright.sync_api import sync_playwright
import json,time
from pathlib import Path
import argparse
parser=argparse.ArgumentParser(description="Private marooning browser acceptance; captures must stay outside public artifacts.")
parser.add_argument("url")
parser.add_argument("captures",type=Path)
args=parser.parse_args()
out=args.captures;out.mkdir(parents=True,exist_ok=True)
with sync_playwright() as p:
 b=p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader'])
 page=b.new_page(viewport={'width':956,'height':440},has_touch=True)
 errors=[]; requests=[]
 page.on('console',lambda m: errors.append(m.text) if m.type=='error' else None)
 page.on('pageerror',lambda e: errors.append(str(e)))
 page.on('request',lambda r:requests.append(r.url))
 page.goto(args.url.rstrip('/')+'/?review')
 page.wait_for_function('window.survivorApp',timeout=120000)
 def state(): return page.evaluate('JSON.parse(window.survivorApp)')
 def waitscreen(s): page.wait_for_function('(s)=>JSON.parse(window.survivorApp).screen===s',arg=s,timeout=120000)
 def tap(key):
  x,y=state()['actions'][key];page.touchscreen.tap(x*956,y*440)
 tap('new');waitscreen('SELECTION');page.touchscreen.tap(790,408)
 page.wait_for_function("JSON.parse(window.survivorApp).actions.standard",timeout=120000)
 tap('standard');page.wait_for_function("JSON.parse(window.survivorApp).actions['Two Tribes']",timeout=120000)
 tap('Two Tribes');page.wait_for_function("JSON.parse(window.survivorApp).actions.marooning",timeout=120000)
 print('validated tribe review',flush=True)
 tap('marooning');waitscreen('MAROONING')
 print('entered',state()['marooning']['actors'],flush=True)
 # Allow one real frame after skip; then use the scene's review cameras.
 x,y=state()['marooning']['controls']['skip'];page.touchscreen.tap(x*956,y*440)
 page.wait_for_function("!JSON.parse(window.survivorApp).marooning.locked",timeout=120000)
 for name in ['exterior','deck','rafts','dock','landing']:
  page.evaluate('(name)=>window.marooningView(name)',name);page.wait_for_timeout(2500);page.screenshot(path=out/(name+'.png'))
  print('capture',name,flush=True)
 page.evaluate("window.marooningView('follow')")
 start=state()['marooning']
 cdp=page.context.new_cdp_session(page)
 x,y=start['controls']['stick']
 left={'x':x*956,'y':y*440,'id':41};right={'x':700,'y':260,'id':92}
 cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[left,right]})
 left['y']-=50;right['x']+=55
 cdp.send('Input.dispatchTouchEvent',{'type':'touchMove','touchPoints':[left,right]})
 page.wait_for_function("s=>{const m=JSON.parse(window.survivorApp).marooning;return m.travel>s.travel+.3&&Math.abs(m.yaw-s.yaw)>.05}",arg=start,timeout=120000)
 cdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]})
 page.wait_for_function("JSON.parse(window.survivorApp).marooning.move_finger===-1&&JSON.parse(window.survivorApp).marooning.look_finger===-1",timeout=120000)
 result=state()
 assert result['season']=='' and result['slot']==0 and result['revision']==0
 x,y=result['marooning']['controls']['Exit Preview'];page.touchscreen.tap(x*956,y*440)
 waitscreen('NEW_GAME')
 tap('marooning');waitscreen('MAROONING')
 assert state()['marooning']['actors']==18
 print('multitouch, no save mutation, exit/reentry passed',flush=True)
 (out/'browser-result.json').write_text(json.dumps({'errors':errors,'requests':requests,'state':state()},indent=2))
 b.close()
 print('errors',errors,flush=True)
