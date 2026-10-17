#!/usr/bin/env python3
"""Execute the actual embedded script with a small browser API test harness."""
import json
import os
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parents[1]
text = (root / 'Tweak.m').read_text()
section = text.split('static NSString *RABWebScript(void) {', 1)[1].split('\n}\n', 1)[0]
script = ''.join(json.loads(s) for s in re.findall(r'"(?:[^"\\]|\\.)*"', section))
harness = r'''
const vm = require('vm');
const assert = require('assert');
const script = SCRIPT;
async function run(host) {
  const events = [], callbacks = [], listeners = {};
  let clicked = 0, hidden = false, observed = false;
  const dialog = {getAttribute: () => hidden ? 'true' : 'false', querySelector: () => ({click(){clicked++;hidden=true;}})};
  const context = {
    URL, Set, queueMicrotask,
    location: {hostname:host, href:'https://'+host+'/'},
    window: {webkit:{messageHandlers:{rabDiagnosticTest1:{postMessage:x=>events.push(x)}}}},
    PerformanceObserver: class {constructor(cb){callbacks.push(cb);} observe(){}},
    MutationObserver: class {constructor(cb){} observe(){observed=true;}},
    document: {readyState:'complete', addEventListener:(n,f)=>listeners[n]=f,
               querySelectorAll: selector => {assert.equal(selector,'.c-dialog--companion-ad');return [dialog];}}
  };
  vm.runInNewContext(script,context,{timeout:2000});
  callbacks[0]({getEntries:()=>[
    {name:'https://rms.deliveryengine.adswizz.com/www/delivery/fc.php?private=SECRET'},
    {name:'https://rms.deliveryengine.adswizz.com/again?private=SECRET'},
    {name:'https://stream.rockantenne.de/rockantenne/stream/mp3?private=SECRET'}]});
  listeners.playing({target:{tagName:'AUDIO',currentSrc:'https://stream.rockantenne.de/rockantenne/stream/mp3?token=SECRET'}});
  await new Promise(resolve=>setImmediate(resolve));
  assert(!JSON.stringify(events).includes('SECRET'));
  assert.equal(events.filter(e=>e.kind==='resource').length,2);
  assert.equal(events.filter(e=>e.kind==='media-playing').length,1);
  return {clicked, observed, events};
}
(async()=>{
  const first = await run('www.rockantenne.de');
  assert.equal(first.clicked,1); assert(first.observed);
  assert(first.events.some(e=>e.kind==='companion-closed'));
  const unrelated = await run('accounts.example.org');
  assert.equal(unrelated.clicked,0); assert(!unrelated.observed);
  console.log('PASS: embedded JS syntax/execution, ad-dialog close, domain isolation, resource deduplication, URL-query redaction');
})().catch(e=>{console.error(e);process.exit(1);});
'''.replace('SCRIPT', json.dumps(script))
node = os.environ.get('CODEX_PRIMARY_RUNTIME_NODE', 'node')
subprocess.run([node, '-e', harness], check=True)
