"""One focused landscape regression. Captures contain restricted private presentation;
keep the output outside public source/Actions artifacts. No account mutation occurs.
Run against an intentionally staged private export served on localhost or private HTTPS.
"""
import argparse
import json
from pathlib import Path
from playwright.sync_api import sync_playwright


def state(page):
    return page.evaluate('JSON.parse(window.survivorApp)')


def wait(page, expression):
    try:
        page.wait_for_function('() => { const a = window.survivorApp && JSON.parse(window.survivorApp); return a && (' + expression + '); }', timeout=90000)
    except Exception:
        print('Failed condition:',expression,'State:',state(page),flush=True)
        raise


def tap(page, key):
    x, y = state(page)['actions'][key]
    assert 0 < x < 1 and 0 < y < 1, (key, x, y)
    page.touchscreen.tap(x * page.viewport_size['width'], y * page.viewport_size['height'])
    page.wait_for_timeout(350)


_option_indices = {"trait":0,"gender":0,"mode":0}


def option(page, key, index):
    tap(page, key)
    delta = index - _option_indices[key]
    for _ in range(abs(delta)):
        page.keyboard.press('ArrowDown' if delta > 0 else 'ArrowUp')
    page.keyboard.press('Enter')
    _option_indices[key] = index
    page.wait_for_timeout(500)


def swipe(page, rect, upward=True):
    x, y, w, h = rect
    width, height = page.viewport_size.values()
    x = (x + w * .65) * width
    begin = (y + h * (.85 if upward else .15)) * height
    end = (y + h * (.15 if upward else .85)) * height
    cdp = page.context.new_cdp_session(page)
    def dispatch(kind, points):
        cdp.send('Input.dispatchTouchEvent', {'type':kind,'touchPoints':points})
    dispatch('touchStart',[{'x':x,'y':begin}])
    for step in range(1,13):
        dispatch('touchMove',[{'x':x,'y':begin+(end-begin)*step/12}])
        page.wait_for_timeout(30)
    dispatch('touchEnd',[])
    cdp.detach()
    page.wait_for_timeout(400)


def reveal(page, key, rect_name='roster_rect'):
    for _ in range(22):
        a=state(page); x,y=a['actions'].get(key,[-1,-1])
        rect=a['selection'][rect_name]
        if rect[1]+.03 < y < rect[1]+rect[3]-.03:
            return
        swipe(page,rect,upward=y >= rect[1]+rect[3]-.03)
    raise AssertionError(('Could not reveal',key,state(page)))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url',default='http://localhost:3000/')
    parser.add_argument('--captures',type=Path,required=True)
    args=parser.parse_args(); args.captures.mkdir(parents=True,exist_ok=True)
    results={}; errors=[]
    with sync_playwright() as p:
        browser=p.chromium.launch(executable_path='/usr/bin/chromium',args=['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader'])
        page=browser.new_page(viewport={'width':956,'height':440},has_touch=True)
        page.on('pageerror',lambda error: errors.append(str(error)))
        page.on('console',lambda m: errors.append(m.text) if m.type=='error' else None)
        page.goto(args.url+'?review',wait_until='domcontentloaded')
        wait(page,'a.screen === "MAIN"')
        print('Checking selection',flush=True)
        tap(page,'new'); wait(page,'a.screen === "SELECTION" && a.selection.eligible.length === 18')
        assert state(page)['ui_font']=='Survivant'
        print('Checking landscape and touch scrolling',flush=True)
        for width,height in [(956,440),(844,390)]:
            page.set_viewport_size({'width':width,'height':height}); page.wait_for_timeout(700)
            a=state(page)
            for key in ('back','random','select'):
                assert .05 < a['actions'][key][1] < .96,(width,key,a)
            page.screenshot(path=args.captures/f'selection-{width}x{height}.png')
            selected=a['selection']['selected_id']
            swipe(page,a['selection']['details_rect'])
            assert state(page)['selection']['details_offset']>0
            assert state(page)['selection']['selected_id']==selected
            swipe(page,state(page)['selection']['details_rect'])
            page.screenshot(path=args.captures/f'attributes-{width}x{height}.png')
            results[f'{width}x{height}']='bottom controls, touch scrolling, selection retained'
            # Changing contestant resets the details scroll without leaving selection.
            tap(page,'cast_2'); wait(page,'a.selection.selected_id === 2')
        page.set_viewport_size({'width':956,'height':440});page.wait_for_timeout(500)
        # Sample the start, middle and end; the headless gate covers all 18 handoffs.
        print('Checking roster endpoints and middle',flush=True)
        for id_ in (1,11,18):
            reveal(page,f'cast_{id_}')
            tap(page,f'cast_{id_}');wait(page,f'a.selection.selected_id === {id_}')
            assert state(page)['selection']['preview']=='3D preview unavailable'
        results['roster_sample']='IDs 1, 11, 18 selected via touch scrolling with own portrait fallback'
        page.screenshot(path=args.captures/'last-contestant.png')
        print('Checking filters and random',flush=True)
        option(page,'trait',1);wait(page,'a.selection.eligible.length === 6')
        option(page,'gender',1)
        a=state(page); eligible=a['selection']['eligible']
        assert eligible and len(eligible)<6 and a['selection']['selected_id'] in eligible
        for _ in range(8):
            tap(page,'random');a=state(page);assert a['selection']['selected_id'] in eligible
        results['filters_random']='trait/gender intersection and 8 eligible random draws'
        option(page,'trait',0);option(page,'gender',0)
        wait(page,'a.selection.eligible.length === 18')
        reveal(page,'cast_11');tap(page,'cast_11');wait(page,'a.selection.selected_id === 11')
        reveal(page,'mode','details_rect');option(page,'mode',1)
        wait(page,'a.selection.mode === "Immersive"')
        tap(page,'select');wait(page,'a.selection.summary && a.season === ""')
        page.screenshot(path=args.captures/'selection-confirmed.png')
        results['confirmation']='Sandra ID 11, Immersive retained, no season'
        tap(page,'back');wait(page,'a.screen === "MAIN"')
        print('Checking repeated navigation and existing menus',flush=True)
        for cycle in range(3):
            tap(page,'new');wait(page,'a.screen === "SELECTION" && a.selection.selected_id === 11 && a.selection.mode === "Immersive"')
            tap(page,'back');wait(page,'a.screen === "MAIN"')
        for key,screen in [('settings','SETTINGS'),('load','SLOTS'),('account','ACCOUNT')]:
            tap(page,key);wait(page,f'a.screen === "{screen}"')
            # Back may be below the scrolled menu on the short landscape viewport.
            for _ in range(12):
                if 0 < state(page)['actions']['back'][1] < .95: break
                page.mouse.move(470,250);page.mouse.wheel(0,240);page.wait_for_timeout(250)
            tap(page,'back');wait(page,'a.screen === "MAIN"')
        results['menus']='three repeated Home cycles; Settings, Load Game, Account'
        print('Checking technical season / Continue',flush=True)
        tap(page,'credits');wait(page,'a.screen === "CREDITS"')
        for _ in range(12):
            if 0 < state(page)['actions']['technical'][1] < .95: break
            page.mouse.move(470,250);page.mouse.wheel(0,160);page.wait_for_timeout(250)
        tap(page,'technical');wait(page,'a.screen === "SLOTS"')
        tap(page,'slot1');wait(page,'a.screen === "SESSION" && a.season !== ""')
        season=state(page)['season']
        # Retain the existing technical Save / Exit / Continue boundary.
        tap(page,'save');tap(page,'menu');wait(page,'a.screen === "MAIN"')
        tap(page,'continue');wait(page,'a.screen === "SESSION"')
        assert state(page)['season']==season
        page.reload();wait(page,'a.screen === "MAIN"')
        tap(page,'continue');wait(page,'a.screen === "SESSION"')
        assert state(page)['season']==season
        results['technical_continue']='create technical slot, Save, Exit, Continue, reload/Continue same season'
        assert not errors,errors
        results['browser_errors']=errors
        (args.captures/'regression.json').write_text(json.dumps(results,indent=2))
        print(json.dumps(results,indent=2))
        browser.close()


if __name__=='__main__': main()
