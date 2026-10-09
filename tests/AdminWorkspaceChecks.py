"""Real browser checks of production panel components with isolated HTTP fixtures."""
import argparse,copy,json
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright,expect
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--url',default='http://127.0.0.1:4173')
parser.add_argument('--output',type=Path,default=Path('build/panel-review'))
args=parser.parse_args()
assert urlparse(args.url).hostname in ('localhost','127.0.0.1'), 'Browser fixtures require a local preview'
out=args.output
out.mkdir(parents=True,exist_ok=True)
phrase='يا رب إن القلب يرجو رحمتك'
job={'id':'fixture-job','trackId':'fixture-track','status':'ready','progressSeconds':90,'errorCode':None,'language':'ar','quality':{'needsReview':True,'model':'fixture model','languageProbability':0.7,'warnings':['LANGUAGE_UNCERTAIN'],'elapsedSeconds':30},'document':{'version':2,'id':'fixture-job','language':'ar','segments':[{'id':'s0','start':2,'end':8,'original':phrase,'words':[],'timing':'phrase'}]}}
track={'id':'fixture-track','title':'Nasheed','artist':'Fixture artist','language':'ar','duration':90,'status':'draft','revision':1,'captionsRevision':0,'captions':[],'updatedAt':'2026-10-09T00:00:00Z','audioUrl':None,'artworkUrl':None,'recognition':{k:v for k,v in job.items() if k not in ('trackId','document')}}
state={'tracks':[track],'submissions':[],'events':[],'total':1,'page':1,'stats':{'published':0,'drafts':1,'pending':0},'recognition':{'enabled':True,'message':'Оригинал распознаётся автоматически.','counts':{'queued':0,'processing':0,'ready':0,'review':1,'failed':0,'missing':0}}}
reports=[]
with sync_playwright() as p:
 browser=p.chromium.launch(headless=True)
 for width,height in [(1440,1000),(393,852)]:
  context=browser.new_context(viewport={'width':width,'height':height})
  page=context.new_page(); actions=[]; errors=[]
  page.on('pageerror',lambda e: errors.append(str(e)))
  def api(route):
   path=urlparse(route.request.url).path
   body={}
   if path=='/_api/auth/session':
    body={'json':{'user':{'id':999,'displayName':'Fixture owner','email':'owner@example.invalid','avatarUrl':None,'role':'admin'}}}
   elif path=='/_api/admin/state': body=state
   elif path=='/_api/admin/action':
    value=route.request.post_data_json; actions.append(copy.deepcopy(value))
    if value['action']=='get-recognition':
     body={'ok':True,'trackRevision':1,'recognition':job,'titleSuggestion':{'title':phrase,'excerpt':phrase,'start':2,'method':'opening','needsReview':True}}
    elif value['action'] in ('save-track','save-captions'): body={'ok':True,'trackId':'fixture-track'}
    else: raise AssertionError('Unexpected mutation '+value['action'])
   else: raise AssertionError('Unexpected API '+path)
   route.fulfill(status=200,content_type='application/json',body=json.dumps(body,ensure_ascii=False))
  page.route('**/_api/**',api)
  page.goto(args.url.rstrip('/')+'/admin')
  expect(page.get_by_role('heading',name='Каталог нашидов')).to_be_visible()
  expect(page.get_by_role('region',name='Распознавание каталога')).to_be_visible()
  expect(page.get_by_text('Текст готов · требуется проверка',exact=False)).to_be_visible()
  if not page.evaluate('document.documentElement.scrollWidth <= window.innerWidth'):
   print('overflow',width,page.evaluate('({width:window.innerWidth,scroll:document.documentElement.scrollWidth,offenders:[...document.querySelectorAll("*")].filter(e=>e.getBoundingClientRect().right>window.innerWidth+1).slice(0,12).map(e=>({tag:e.tagName,cls:e.className,right:e.getBoundingClientRect().right}))})'),flush=True)
   page.screenshot(path=str(out/f'overflow-{width}.png'),full_page=True)
   raise AssertionError('Panel has horizontal overflow')
  page.screenshot(path=str(out/f'catalog-{width}.png'),full_page=True)
  page.get_by_role('button',name='Изменить',exact=True).click()
  expect(page.get_by_role('region',name='Предложение названия')).to_be_visible()
  title=page.get_by_role('textbox',name='Название',exact=True)
  expect(title).to_have_value('Nasheed')
  assert 'serif' not in page.get_by_role('dialog').evaluate('(element)=>getComputedStyle(element).fontFamily').split(',')[0], 'Dialog lost the panel font'
  assert page.get_by_role('dialog').evaluate('(element)=>element.scrollWidth <= element.clientWidth'), 'Dialog fields overflow their container'
  page.get_by_role('button',name='Подставить название').click()
  expect(title).to_have_value(phrase)
  assert not any(a['action']=='save-track' for a in actions), 'Title was saved without an explicit save'
  page.screenshot(path=str(out/f'title-suggestion-{width}.png'),full_page=True)
  page.get_by_role('button',name='Сохранить',exact=True).click()
  expect(page.get_by_role('heading',name='Редактировать нашид')).not_to_be_visible()
  saved=next(a for a in actions if a['action']=='save-track')
  assert saved['title']==phrase and saved['revision']==1
  page.get_by_role('button',name='Субтитры: Nasheed',exact=True).click()
  expect(page.get_by_text('Текст готов · требуется проверка',exact=True)).to_be_visible()
  page.get_by_role('button',name='Взять распознанный текст').click()
  assert phrase in page.locator('textarea').evaluate_all('(items)=>items.map(item=>item.value)'), 'Arabic original missing in editor'
  assert not any(a['action']=='save-captions' for a in actions), 'Recognition overwrote captions without owner save'
  page.screenshot(path=str(out/f'caption-review-{width}.png'),full_page=True)
  page.get_by_role('button',name='Сохранить субтитры',exact=True).click()
  expect(page.get_by_role('heading',name='Субтитры · Nasheed')).not_to_be_visible()
  saved=next(a for a in actions if a['action']=='save-captions')
  assert saved['captions']==[{'start':2,'end':8,'ar':phrase,'ru':'','en':''}]
  assert not errors,errors
  reports.append({'viewport':[width,height],'fixtureOnly':True,'javascriptErrors':errors,'checks':['recognition counts','review warning','no horizontal overflow','Arabic title suggestion','no autosave','explicit title save with revision','original Arabic caption import','explicit caption save with revision']})
  context.close()
 browser.close()
(out/'verification.json').write_text(json.dumps({'scope':'Production panel rendered in Chromium with controlled API fixtures; live backend authorization is tested separately','results':reports},ensure_ascii=False,indent=2))
print(json.dumps({'viewports':len(reports),'checksPerViewport':8,'result':'passed'}))
