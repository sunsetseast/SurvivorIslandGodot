"""Private GUI acceptance: read-only telemetry; actions use browser touch input."""
import argparse,json,math,time,os,sys,termios
from urllib.parse import urlsplit
from pathlib import Path
from playwright.sync_api import sync_playwright
ap=argparse.ArgumentParser();ap.add_argument('url');ap.add_argument('out',type=Path);ap.add_argument('--tribes',type=int,default=2);ap.add_argument('--site-auth-stdin',action='store_true');args=ap.parse_args();args.out.mkdir(parents=True,exist_ok=True)
credential=None
if args.site_auth_stdin:
 settings=termios.tcgetattr(sys.stdin);settings[3]&=~termios.ECHO;termios.tcsetattr(sys.stdin,termios.TCSANOW,settings)
 print('Ready for scoped Site service credential JSON on hidden stdin',flush=True)
 credential=json.loads(sys.stdin.readline())['credential']
 assert urlsplit(args.url).scheme=='https'
with sync_playwright() as p:
 launch_options={}
 if credential and os.environ.get('HTTPS_PROXY'):launch_options['proxy']={'server':os.environ['HTTPS_PROXY']}
 browser=p.chromium.launch(**launch_options,executable_path='/usr/bin/chromium',args=['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader'])
 context=browser.new_context(viewport={'width':956,'height':440},device_scale_factor=.25,has_touch=True,record_video_dir=str(args.out),record_video_size={'width':956,'height':440})
 if credential:
  origin=urlsplit(args.url).netloc
  context.route('**/*',lambda route:route.continue_() if urlsplit(route.request.url).netloc==origin else route.abort())
  context.set_extra_http_headers({'OAI-Sites-Authorization':'Bearer '+credential})
 page=context.new_page();page.set_default_timeout(120000);errors=[];trace=[];captures=[]
 page.on('pageerror',lambda e:errors.append(str(e)));page.on('console',lambda e:errors.append(e.text) if e.type=='error' else None)
 page.goto(args.url.rstrip('/')+'/?review');page.wait_for_function('window.survivorApp',timeout=120000)
 def state():return page.evaluate('JSON.parse(window.survivorApp)')
 def scene():return state()['marooning']
 def tap(key,game=True):
  row=scene()['controls'] if game else state()['actions']
  if key not in row:return False
  x,y=row[key];page.touchscreen.tap(x*956,y*440);page.wait_for_timeout(150);return True
 def capture(name,view=None):
  if view:page.evaluate('(v)=>window.marooningView(v)',view);page.wait_for_timeout(500)
  page.screenshot(path=str(args.out/(name+'.png')),timeout=120000);captures.append(name);print('CAPTURE',name,flush=True)
 tap('new',False);page.wait_for_function("JSON.parse(window.survivorApp).screen==='SELECTION'")
 # Select an actual roster row through scrolling and touch; no setup mutation.
 page.mouse.move(180,240)
 for i in range(8):
  s=state();pt=s['actions'].get('cast_18')
  if pt and .20<pt[1]<.85:tap('cast_18',False);break
  page.mouse.wheel(0,350);page.wait_for_timeout(250)
 tap('select',False);page.wait_for_function('JSON.parse(window.survivorApp).actions.standard');tap('standard',False)
 page.wait_for_function("JSON.parse(window.survivorApp).actions['Two Tribes']");tap('Two Tribes' if args.tribes==2 else 'Three Tribes',False)
 page.wait_for_function('JSON.parse(window.survivorApp).actions.marooning');tap('marooning',False)
 page.wait_for_function("JSON.parse(window.survivorApp).screen==='MAROONING'");tap('skip');page.wait_for_function('!JSON.parse(window.survivorApp).marooning.locked')
 capture('ready-baskets','deck');page.evaluate("window.marooningView('follow')")
 cdp=context.new_cdp_session(page)
 def event(kind,points):cdp.send('Input.dispatchTouchEvent',{'type':kind,'touchPoints':points})
 def walk(gx,gz,tol=1.0,limit=45,moving=None):
  s=scene();hx,hy=s['controls']['stick'];h={'x':hx*956,'y':hy*440,'id':41};event('touchStart',[h])
  result=False
  for attempt in range(limit):
   if s['race_phase']==3 or s['aboard']:result=True;break
   if moving:gx,gz=moving(s)
   dx,dz=gx-s['x'],gz-s['z'];distance=math.hypot(dx,dz)
   if distance<tol:result=True;break
   yaw=s.get('move_heading',s['yaw']);x=(dx*math.cos(yaw)-dz*math.sin(yaw))/distance;y=(dx*math.sin(yaw)+dz*math.cos(yaw))/distance
   power=.8 if distance>6 else max(.19,distance/14)
   event('touchMove',[{'x':h['x']+x*45*power,'y':h['y']+y*45*power,'id':41}])
   try:page.wait_for_function('(v)=>{let s=JSON.parse(window.survivorApp).marooning;return s.race_phase===3||s.travel>v;}',arg=s['travel']+max(.25,min(4.5,distance*.5)),timeout=12000)
   except Exception:print('NO_PROGRESS',attempt,gx,gz,flush=True)
   s=scene();trace.append({'goal':[gx,gz],'position':[s['x'],s['y'],s['z']],'scramble_elapsed':s['scramble_elapsed'],'race_elapsed':s['race_elapsed']})
   print('WALK',round(s['x'],2),round(s['z'],2),'goal',gx,gz,'timer',s['scramble_elapsed'],s['race_elapsed'],flush=True)
  event('touchEnd',[])
  return result
 def look(point):
  s=scene();dx,dz=point[0]-s['x'],point[2]-s['z'];goal=math.atan2(-dx,-dz);angle=(goal-s['yaw']+math.pi)%(2*math.pi)-math.pi
  pitch=math.atan2(point[1]-(s['y']+1.43),max(.1,math.hypot(dx,dz)));pitch=max(-1,min(.42,pitch));vertical=-(pitch-s.get('pitch',-.31))*440/(2.07*.87)
  home={'x':760,'y':240,'id':92};event('touchStart',[home]);event('touchMove',[dict(home,x=home['x']-angle*440/2.07,y=home['y']+vertical)]);page.wait_for_timeout(500);event('touchEnd',[])
 # Inspect and approach an actual supply while the challenge clock is still stopped.
 initial=scene();candidate=min(initial['supply_state']['items'],key=lambda i:math.hypot(i['position'][0]-initial['x'],i['position'][2]-initial['z']))
 walk(candidate['position'][0],candidate['position'][2],1.1,12)
 point=candidate['position'].copy();point[1]+=.2;look(point)
 tap('start')
 s=scene();hx,hy=s['controls']['stick'];home={'x':hx*956,'y':hy*440,'id':41};right={'x':780,'y':220,'id':92}
 event('touchStart',[home,right]);event('touchMove',[dict(home,y=home['y']-12),dict(right,x=792)]);page.wait_for_timeout(300);event('touchEnd',[])
 after=scene();assert after['travel']>s['travel'] and abs(after['yaw']-s['yaw'])>.01,'Dual touch must change movement and camera'
 print('STARTED',after['selected'],after['scramble_elapsed'],flush=True)
 for cycle in range(3):
  for attempt in range(3):
   s=scene();supply=s['supply_state']
   if s['scramble_phase']!=2:break
   if supply['carried']:break
   candidates=[i for i in supply['items'] if i['state'] in [0,2]]
   if cycle==1:candidates=[i for i in candidates if math.dist([i['position'][0],i['position'][2]],[supply['basket'][0],supply['basket'][2]])>2]
   if not candidates:break
   item=min(candidates,key=lambda i:math.hypot(i['position'][0]-s['x'],i['position'][2]-s['z']))
   walk(item['position'][0],item['position'][2],1.1,12);point=item['position'].copy();point[1]+=.2;look(point);page.wait_for_timeout(100)
   if 'interact' in scene()['controls']:
    tap('interact');page.wait_for_timeout(1200);capture(f'target-or-pickup-{cycle}-{attempt}')
  s=scene();supply=s['supply_state']
  if not supply['carried']:continue
  capture(f'carrying-{cycle}')
  if cycle==1 and 'drop' in s['controls']:
   tap('drop');page.wait_for_timeout(1300);capture('drop')
   if 'interact' in scene()['controls']:tap('interact');page.wait_for_timeout(1800)
  s=scene();basket=s['supply_state']['basket']
  if s['supply_state']['carried']:
   walk(basket[0]-math.copysign(1.05,basket[0]),basket[2],.75,22);page.wait_for_timeout(2000);capture(f'deposit-{cycle}')
 # Deliberately aim at a nearby moving carrier and attempt theft through the primary action.
 s=scene()
 if not s['supply_state']['carried'] and s['scramble_phase']==2:
  carried=[i for i in s['supply_state']['items'] if i['state']==1 and i['actor']!=s['selected']]
  if carried:
   item=min(carried,key=lambda i:math.hypot(i['position'][0]-s['x'],i['position'][2]-s['z']))
   walk(item['position'][0],item['position'][2],1.2,12);point=item['position'].copy();point[1]+=.95;look(point);page.wait_for_timeout(250)
   if scene()['supply_state']['action']=='steal':tap('interact');page.wait_for_timeout(1200);capture('theft-feedback')
 capture('crowd-circulation','deck');page.evaluate("window.marooningView('follow')")
 # Preparing at the safe exit before expiry is ordinary play, and avoids wasting assembly time on automation reads.
 if scene()['scramble_phase']==2:walk(0,7.5,.4,25)
 page.wait_for_function('JSON.parse(window.survivorApp).marooning.scramble_phase===3',timeout=180000);capture('boarding-guidance')
 walk(0,7.5,.65,25);walk(0,10.5,.8,15);walk(0,25,1.4,20)
 s=scene();bx,bz=s['boarding_position'];outside=bx+math.copysign(4.5,bx)
 walk(outside,25,1.3,25);walk(bx+math.copysign(4,bx),bz+2,1.0,15)
 if 'board' in scene()['controls']:tap('board');page.wait_for_timeout(1500)
 assert scene()['aboard'],'Human must board through the GUI'
 before_focus=scene();hx,hy=before_focus['controls']['stick'];h={'x':hx*956,'y':hy*440,'id':41}
 event('touchStart',[h]);event('touchMove',[dict(h,y=h['y']-20)])
 other=context.new_page();other.goto('about:blank');other.bring_to_front();page.wait_for_timeout(1500)
 frozen=scene();page.bring_to_front();page.wait_for_timeout(500);event('touchEnd',[]);other.close()
 resumed=scene();assert resumed['move_finger']==-1 and resumed['look_finger']==-1,'Focus restore must clear pointer ownership'
 print('FOCUS',before_focus['race_elapsed'],frozen['race_elapsed'],resumed['race_elapsed'],flush=True)
 page.wait_for_function('JSON.parse(window.survivorApp).marooning.race_phase!==0',timeout=100000)
 for cycle in range(3):
  if 'paddle' in scene()['controls']:tap('paddle');page.wait_for_timeout(1700)
 capture('paddle-ui');page.set_viewport_size({'width':812,'height':375});page.wait_for_timeout(1000);capture('small-landscape');page.set_viewport_size({'width':956,'height':440})
 if 'jump_off' in scene()['controls']:
  tap('jump_off')
  # Reboard promptly; taking a screenshot first lets a fast raft travel away during software rendering.
  try:
   page.wait_for_function("JSON.parse(window.survivorApp).marooning.controls.board",timeout=5000)
   tap('board');page.wait_for_function("JSON.parse(window.survivorApp).marooning.aboard",timeout=10000)
  except Exception:print('REBOARD_NOT_REACHED',scene()['race_actor'],flush=True)
  capture('moving-reboard')
 capture('loaded-raft','raft-side');page.evaluate("window.marooningView('follow')")
 saw_reward=False
 for tick in range(1200):
  page.wait_for_timeout(1000);s=scene()
  if s['reward'] and not saw_reward:capture('reward-claimed','race');page.evaluate("window.marooningView('follow')");saw_reward=True
  if s['reward'] and not s['aboard'] and s['race_phase']==2:
   goal=s['arrival_position']
   if s['z']<163:walk(8,165,1,70)
   walk(goal[0],goal[1],2,45)
  if tick%20==0:print('RACE_PROGRESS',s['race_elapsed'],s['race_phase'],s['reward'],s['x'],s['z'],s['race_actor'],flush=True)
  (args.out/'latest-state.json').write_text(json.dumps(state(),indent=2))
  if s['race_phase']==3:break
  if s['race_elapsed']>420:break
 assert scene()['race_phase']==3,'Arrival must be observed'
 capture('arrival-summary','landing');final=state();assert final['season']=='' and final['slot']==0 and final['revision']==0
 assert scene()['race_actor']['boardings']>=2,'Moving reboarding must be observed'
 (args.out/'observed.json').write_text(json.dumps({'state':final,'errors':errors,'trace':trace,'captures':captures},indent=2))
 tap('Exit Preview');page.wait_for_function("JSON.parse(window.survivorApp).screen==='NEW_GAME'");print('BROWSER_COMPLETE',scene() if state().get('marooning') else 'NEW_GAME','errors',errors,flush=True)
 context.close();browser.close()
