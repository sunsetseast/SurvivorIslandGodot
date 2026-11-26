"""Private browser acceptance. Captures must remain outside public commits/artifacts.
Camera-only review hooks do not execute gameplay actions. All actions below use touch.
"""
from pathlib import Path
import argparse,json,time
from playwright.sync_api import sync_playwright
parser=argparse.ArgumentParser()
parser.add_argument('url')
parser.add_argument('captures',type=Path)
args=parser.parse_args()
out=args.captures;out.mkdir(parents=True,exist_ok=True)
with sync_playwright() as p:
    browser=p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader'])
    page=browser.new_page(viewport={'width':956,'height':440},has_touch=True)
    page.set_default_timeout(120000)
    errors=[]
    page.on('pageerror',lambda e:errors.append(str(e)))
    page.on('console',lambda m:errors.append(m.text) if m.type=='error' else None)
    page.goto(args.url.rstrip('/')+'/?review')
    page.wait_for_function('window.survivorApp',timeout=120000)
    def state():return page.evaluate('JSON.parse(window.survivorApp)')
    def tap(key,marooning=False):
        s=state();x,y=(s['marooning']['controls'] if marooning else s['actions'])[key]
        page.touchscreen.tap(x*956,y*440)
    tap('new')
    page.wait_for_function("JSON.parse(window.survivorApp).screen==='SELECTION'",timeout=120000)
    page.touchscreen.tap(790,408)
    page.wait_for_function('JSON.parse(window.survivorApp).actions.standard',timeout=120000);tap('standard')
    page.wait_for_function("JSON.parse(window.survivorApp).actions['Two Tribes']",timeout=120000);tap('Two Tribes')
    page.wait_for_function('JSON.parse(window.survivorApp).actions.marooning',timeout=120000);tap('marooning')
    page.wait_for_function("JSON.parse(window.survivorApp).screen==='MAROONING'",timeout=120000)
    tap('skip',True)
    page.wait_for_function('!JSON.parse(window.survivorApp).marooning.locked',timeout=120000)
    page.screenshot(path=str(out/'loaded-ship.png'))
    tap('start',True)
    cdp=page.context.new_cdp_session(page)
    s=state()['marooning'];x,y=s['controls']['stick'];left={'x':x*956,'y':y*440,'id':41};right={'x':700,'y':220,'id':92}
    cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[left,right]})
    left['y']-=45;right['x']+=45
    cdp.send('Input.dispatchTouchEvent',{'type':'touchMove','touchPoints':[left,right]})
    page.wait_for_timeout(1500)
    cdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]})
    after=state()['marooning']
    assert after['travel']>s['travel'] and abs(after['yaw']-s['yaw'])>.01
    page.evaluate("window.marooningView('deck')")
    page.screenshot(path=str(out/'supply-gameplay.png'))
    seen=set()
    for i in range(300):
        page.wait_for_timeout(3000)
        s=state()['marooning']
        print('OBSERVED',s['scramble_elapsed'],s['race_elapsed'],s['race_phase'],s['reward'],flush=True)
        if s['scramble_phase']==3 and 'raft' not in seen:
            for view in ['raft-side','raft-overhead','race']:
                page.evaluate('(v)=>window.marooningView(v)',view)
                page.wait_for_timeout(1000)
                page.screenshot(path=str(out/(view+'.png')))
            seen.add('raft')
        if s['reward'] and 'reward' not in seen:
            page.screenshot(path=str(out/'reward-claimed.png'));seen.add('reward')
        if s['race_elapsed']>180:break
    result=state()
    assert result['season']=='' and result['slot']==0 and result['revision']==0
    (out/'observed.json').write_text(json.dumps({'state':result,'errors':errors,'dual_touch':True},indent=2))
    tap('Exit Preview',True)
    page.wait_for_function("JSON.parse(window.survivorApp).screen==='NEW_GAME'",timeout=120000)
    print('Browser touch and exit complete; errors:',errors,flush=True)
    browser.close()
