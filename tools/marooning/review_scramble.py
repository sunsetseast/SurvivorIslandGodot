from playwright.sync_api import sync_playwright
from pathlib import Path
import json,time,argparse
parser=argparse.ArgumentParser(description="Private supply scramble touch acceptance; captures must never enter public artifacts.")
parser.add_argument("url")
parser.add_argument("captures",type=Path)
args=parser.parse_args()
out=args.captures;out.mkdir(parents=True,exist_ok=True)
with sync_playwright() as p:
 b=p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader'])
 page=b.new_page(viewport={'width':956,'height':440},has_touch=True)
 errors=[]
 page.on('pageerror',lambda e:errors.append(str(e)))
 page.on('console',lambda m:errors.append(m.text) if m.type=='error' else None)
 page.goto(args.url.rstrip('/')+'/?review')
 page.wait_for_function('window.survivorApp',timeout=120000)
 def state():return page.evaluate('JSON.parse(window.survivorApp)')
 def tap(k):
  x,y=state()['actions'][k];page.touchscreen.tap(x*956,y*440)
 def mtap(k):
  x,y=state()['marooning']['controls'][k];page.touchscreen.tap(x*956,y*440)
 tap('new');page.wait_for_function("JSON.parse(window.survivorApp).screen==='SELECTION'",timeout=120000)
 page.touchscreen.tap(790,408)
 page.wait_for_function('JSON.parse(window.survivorApp).actions.standard',timeout=120000);tap('standard')
 page.wait_for_function("JSON.parse(window.survivorApp).actions['Two Tribes']",timeout=120000);tap('Two Tribes')
 page.wait_for_function('JSON.parse(window.survivorApp).actions.marooning',timeout=120000);tap('marooning')
 page.wait_for_function("JSON.parse(window.survivorApp).screen==='MAROONING'",timeout=120000)
 mtap('skip');page.wait_for_function('!JSON.parse(window.survivorApp).marooning.locked',timeout=120000)
 mtap('start');page.wait_for_timeout(2000)
 print('started',state()['marooning'],flush=True)
 cdp=page.context.new_cdp_session(page)
 x,y=state()['marooning']['controls']['stick'];left={'x':x*956,'y':y*440,'id':41};right={'x':700,'y':260,'id':92}
 before=state()['marooning'];cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[left,right]})
 left['y']-=45;right['x']+=45;cdp.send('Input.dispatchTouchEvent',{'type':'touchMove','touchPoints':[left,right]})
 page.wait_for_timeout(1200);cdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]})
 after=state()['marooning'];assert after['travel']>before['travel'] and abs(after['yaw']-before['yaw'])>.01
 page.screenshot(path=str(out/'gameplay.png'))
 # Actual touch contextual pickup when in range, without teleports.
 if 'interact' in state()['marooning']['controls']:
  mtap('interact');page.wait_for_timeout(2500)
 page.evaluate("window.marooningView('deck')");page.wait_for_timeout(1000);page.screenshot(path=str(out/'npc-cargo.png'))
 for i in range(180):
  page.wait_for_timeout(4000)
  s=state()['marooning'];print('elapsed',s['scramble_elapsed'],'events',s['events'],flush=True)
  if s['scramble_phase']==3:break
 assert state()['marooning']['scramble_phase']==3
 page.screenshot(path=str(out/'results.png'))
 result=state();assert result['season']=='' and result['slot']==0 and result['revision']==0
 (out/'observed.json').write_text(json.dumps({'before':before,'after':after,'result':result,'errors':errors},indent=2))
 mtap('restart');page.wait_for_timeout(3000);assert state()['marooning']['intro']
 mtap('Exit Preview');page.wait_for_function("JSON.parse(window.survivorApp).screen==='NEW_GAME'")
 print('complete; restart and teardown passed; errors',errors,flush=True)
 b.close()
