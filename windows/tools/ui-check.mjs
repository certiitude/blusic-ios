// Exercise the real desktop renderer in an isolated library, never the user's profile.
import {_electron as electron} from 'playwright-core';
import {mkdtemp, mkdir, writeFile, readFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import assert from 'node:assert/strict';
const temp=process.env.TEMP||process.env.TMP;
const directory=await mkdtemp(join(temp,'soryn-ui-refresh-'));
const output=resolve('test-output/ui-1.1');await mkdir(output,{recursive:true});
const env={...process.env};delete env.ELECTRON_RUN_AS_NODE;
const executablePath=process.env.SORYN_TEST_EXE||resolve('node_modules/electron/dist/electron.exe');
const args=[...(process.env.SORYN_TEST_EXE?[]:['.']),'--test-data',directory];
const checks=[],errors=[];let app;
try {
  app=await electron.launch({executablePath,args,env,timeout:60000});
  const page=await app.firstWindow();page.on('pageerror',e=>errors.push(e.message));
  await page.waitForSelector('.home-heading h1');
  assert.equal(await page.locator('.album-card').count(),4);
  assert.equal(await page.locator('#now-panel').isVisible(),false);
  await page.screenshot({path:join(output,'home-1440.png')});checks.push('home shows real library artwork; optional queue initially closed');
  await page.click('[data-home-filter=playlists]');assert.equal(await page.locator('.hero').count(),0);assert.equal(await page.locator('.playlist-card[data-view]').count(),1);
  await page.click('[data-home-filter=music]');assert.equal(await page.locator('.playlist-grid').count(),0);assert.equal(await page.locator('.album-card').count(),4);
  await page.click('[data-home-filter=all]');checks.push('home tabs genuinely filter music and playlists');
  await page.click('#navigation [data-view=library]');await page.fill('#collection-search','apres');
  assert.equal(await page.locator('.track-table tbody tr').count(),1);assert.match(await page.locator('.track-cell strong').innerText(),/Après la pluie/);
  await page.fill('#collection-search','nothing-matches');await page.waitForSelector('[data-clear-filter]');await page.click('[data-clear-filter]');assert.equal(await page.locator('.track-table tbody tr').count(),4);
  assert.equal(await page.locator('#collection-search').evaluate(el=>el===document.activeElement),true);checks.push('accent-insensitive local search, honest empty state and reset preserve keyboard focus');
  await page.selectOption('#collection-sort','title');assert.match(await page.locator('.track-cell strong').first().innerText(),/Après la pluie/);
  await page.click('[data-layout=grid]');assert.equal(await page.locator('#track-results .album-card').count(),4);await page.screenshot({path:join(output,'library-grid.png')});
  await page.click('[data-layout=list]');await page.screenshot({path:join(output,'library-list.png')});checks.push('library sort and grid/list layouts work without changing saved order');
  await page.fill('#collection-search','orbite');await page.click('#play-selection');await page.waitForFunction(()=>!document.querySelector('#audio').paused&&document.querySelector('#audio').currentTime>.1,null,{timeout:15000});
  assert.equal(await page.locator('#player-title').innerText(),'Orbite');assert.equal(await page.locator('#queue-count').innerText(),'0 titre');await page.click('#play');
  checks.push('play all respects the visible filtered collection and queue shows only upcoming tracks');
  await page.click('#new-playlist');await page.fill('#playlist-name','Nuits bleues');await page.click('#modal-actions button');await page.waitForSelector('.collection-heading h1');
  const state=await page.evaluate(()=>window.soryn.call('state')),playlist=state.library.playlists.find(p=>p.name==='Nuits bleues');
  for(const track of state.library.tracks.slice(0,3))await page.evaluate(input=>window.soryn.call('playlist-add',input),{playlistID:playlist.id,track});
  await page.waitForFunction(()=>document.querySelectorAll('.track-table tbody tr').length===3);await page.screenshot({path:join(output,'playlist.png')});
  assert.match(await page.locator('.playlist-link.active strong').innerText(),/Nuits bleues/);checks.push('playlist sleeve, metadata, active navigation and membership use the real library');
  await page.click('#play-selection');await page.waitForFunction(()=>!document.querySelector('#audio').paused,null,{timeout:15000});await page.click('#player-like');
  await page.click('#queue-toggle');assert.equal(await page.locator('#queue-toggle').getAttribute('aria-expanded'),'true');assert.equal(await page.locator('#queue-count').innerText(),'2 titres');
  await page.screenshot({path:join(output,'now-playing-1440.png')});await page.click('#play');
  await page.click('#lyrics');assert.equal(await page.locator('#modal').evaluate(n=>n.open),true);assert.match(await page.locator('.lyrics-content').innerText(),/instrumental/);await page.click('#modal-close');
  checks.push('player favorites, upcoming queue and readable saved-lyrics dialog remain functional');
  for(const [width,height] of [[1280,800],[1000,700],[980,680]]) {
    await page.setViewportSize({width,height});
    if(await page.locator('#panel-close').isVisible())await page.click('#panel-close');await page.click('.brand');
    await page.screenshot({path:join(output,`home-${width}.png`)});
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
    for(const selector of ['#navigation [data-view=library]','.sidebar [data-view=settings]','#play','#volume']) {
      const box=await page.locator(selector).boundingBox();assert.ok(box&&box.x>=0&&box.y>=0&&box.x+box.width<=width+1&&box.y+box.height<=height+1,`${selector} fits ${width}×${height}`);
    }
    await page.click('#queue-toggle');assert.equal(await page.locator('#now-panel').isVisible(),true);
    assert.equal(await page.locator('#queue-toggle').getAttribute('aria-expanded'),'true');
    await page.screenshot({path:join(output,`queue-${width}.png`)});
    await page.press('body','Escape');assert.equal(await page.locator('#now-panel').isVisible(),false);
  }
  checks.push('1280×800, 1000×700 and 980×680 layouts: no document overflow, reachable settings and transport, usable queue overlay');
  await page.click('#navigation [data-view=favorites]');assert.equal(await page.locator('.track-table tbody tr').count(),1);await page.screenshot({path:join(output,'favorites.png')});
  await page.click('.sidebar [data-view=sync]');await page.waitForSelector('#start-sync');await page.screenshot({path:join(output,'sync.png')});
  await page.click('.sidebar [data-view=settings]');await page.selectOption('#rate','1.25');assert.equal(await page.locator('#audio').evaluate(a=>a.playbackRate),1.25);
  await page.press('body','Control+k');assert.equal(await page.locator('#search').evaluate(el=>el===document.activeElement),true);
  checks.push('favorites, sync/settings navigation, playback speed and Ctrl+K remain accessible');
  await page.click('#navigation [data-view=library]');await page.selectOption('#collection-sort','artist');await page.click('[data-layout=grid]');
  await page.emulateMedia({reducedMotion:'reduce'});assert.equal(await page.locator('.album-cover img').first().evaluate(n=>getComputedStyle(n).transitionDuration),'0s');
  await app.close();app=null;
  const saved=JSON.parse(await readFile(join(directory,'library.json'),'utf8'));assert.deepEqual(saved.tracks.map(t=>t.title),['Bleu nuit','Après la pluie','Orbite','Dernier métro']);
  app=await electron.launch({executablePath,args,env,timeout:60000});const reopened=await app.firstWindow();await reopened.waitForSelector('.home-heading h1');await reopened.click('#navigation [data-view=library]');
  assert.equal(await reopened.locator('[data-layout=grid]').getAttribute('aria-pressed'),'true');assert.equal(await reopened.locator('#collection-sort').inputValue(),'artist');checks.push('view preferences survive restart, saved track order unchanged, reduced-motion respected');
  assert.deepEqual(errors,[]);console.log(JSON.stringify({passed:checks,rendererErrors:errors},null,2));await writeFile(join(output,'ui-results.json'),JSON.stringify({passed:checks,rendererErrors:errors},null,2));
} catch(error) {
  const page=app?.windows()[0];
  if(page){await page.screenshot({path:join(output,'failure.png')});console.error(await page.evaluate(()=>({toast:document.querySelector('#toast')?.textContent,title:document.querySelector('#player-title')?.textContent,audio:{src:document.querySelector('#audio').src,paused:document.querySelector('#audio').paused,time:document.querySelector('#audio').currentTime,error:document.querySelector('#audio').error?.message}})));}
  console.error({checks,errors});throw error;
} finally {await app?.close();}
