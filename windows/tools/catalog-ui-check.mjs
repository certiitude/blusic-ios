import {_electron as electron} from 'playwright-core';
import {mkdtemp,mkdir,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import assert from 'node:assert/strict';
const directory=await mkdtemp(join(process.env.TEMP,'soryn-catalog-ui-')),output=resolve('test-output/ui-1.1');await mkdir(output,{recursive:true});
const env={...process.env};delete env.ELECTRON_RUN_AS_NODE;
const executablePath=process.env.SORYN_TEST_EXE||resolve('node_modules/electron/dist/electron.exe');
let app;const passed=[],errors=[];
try{
  app=await electron.launch({executablePath,args:[...(process.env.SORYN_TEST_EXE?[]:['.']),'--test-data',directory],env,timeout:60000});
  const page=await app.firstWindow();page.on('pageerror',e=>errors.push(e.message));await page.waitForSelector('.home-heading h1');
  const status=await page.evaluate(()=>window.soryn.call('state'));assert.equal(status.audioSources.relayConfigured,true);assert.equal(status.audioSources.invidious.length,3);assert.equal(JSON.stringify(status).includes('app.ios.'),false);passed.push('bundled application relay and Invidious configured; application access excluded from renderer state');
  await page.fill('#search','Damso');await page.press('#search','Enter');await page.waitForSelector('.track-table tbody tr',{timeout:25000});const initial=await page.locator('.track-table tbody tr').count();assert.ok(initial>0);
  if(await page.locator('#catalog-more').count()){await page.click('#catalog-more');await page.waitForFunction(initial=>document.querySelectorAll('.track-table tbody tr').length>initial,initial,{timeout:25000});passed.push('actual song-search pagination appends new results');}
  await page.screenshot({path:join(output,'catalog-songs.png')});passed.push('real YouTube Music songs rendered in the desktop library');
  for(const kind of ['albums','artists','playlists']){
    await page.click(`[data-catalog-kind=${kind}]`);await page.waitForSelector('.catalog-card',{timeout:25000});assert.ok(await page.locator('.catalog-card').count()>0);await page.screenshot({path:join(output,`catalog-${kind}.png`)});passed.push(`live ${kind} search returns catalogue cards`);
    if(kind==='albums'){
      await page.locator('.catalog-card').first().click();await page.waitForSelector('.track-table tbody tr',{timeout:25000});const tracks=await page.locator('.track-table tbody tr').count();assert.ok(tracks>0);await page.screenshot({path:join(output,'catalog-album-open.png')});
      await page.click('#catalog-save');await page.waitForSelector('.playlist-link.active');assert.equal(await page.locator('.track-table tbody tr').count(),tracks);passed.push('actual album browse and import into a local playlist preserve its loaded songs');
      await page.click('#navigation [data-view=explore]');
    }
    if(kind==='playlists'){
      await page.locator('.catalog-card').first().click();await page.waitForSelector('.track-table tbody tr',{timeout:25000});
      const count=await page.locator('.track-table tbody tr').count();assert.ok(count>0);
      if(await page.locator('#catalog-browse-more').count()){await page.click('#catalog-browse-more');await page.waitForFunction(n=>document.querySelectorAll('.track-table tbody tr').length>n,count,{timeout:25000});}
      await page.screenshot({path:join(output,'catalog-playlist-open.png')});passed.push('real public YouTube Music playlist opens with its own tracks, with shelf pagination only when available');
    }
  }
  await page.click('.sidebar [data-view=settings]');await page.locator('h2:text("Sources audio préconfigurées")').scrollIntoViewIfNeeded();await page.screenshot({path:join(output,'sources-configured.png')});
  assert.deepEqual(errors,[]);console.log(JSON.stringify({passed,rendererErrors:errors},null,2));await writeFile(join(output,'catalog-ui-results.json'),JSON.stringify({passed,rendererErrors:errors},null,2));
}catch(error){const page=app?.windows()[0];if(page){await page.screenshot({path:join(output,'catalog-failure.png')});console.error(await page.locator('#toast').innerText());}console.error({passed,errors});throw error;}
finally{await app?.close();}
