const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(__dirname+'/../runner-src/scripts/runner-client.js','utf8');
const body=source.match(/async function exportRecord\(r\)\{[\s\S]*?\n\}/)[0];
const full='FIRST\n'+('native progress\n'.repeat(30000))+'LAST';
const original={id:'real-export-check',log:'only tail'};let downloaded,requested;
const context={fleetPrefix:'',encodeURIComponent,fetch:async url=>{requested=url;return{ok:true,text:async()=>full}},recordText:r=>r.log,downloadText:(name,text)=>{downloaded={name,text}},handleError:e=>{throw e}};
vm.createContext(context);const run=vm.runInContext(body+';exportRecord',context);
run(original).then(()=>{assert.equal(requested,'/api/jobs/real-export-check/log');assert.equal(downloaded.text,full);assert.equal(original.log,'only tail');assert.equal(downloaded.name,'real-export-check-record.log');console.log('Full export reads complete log on explicit download; polling snapshot remains untouched');}).catch(e=>{console.error(e);process.exitCode=1});
