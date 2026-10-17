#!/usr/bin/env python3
"""Build a flat jailbreak APT repository. Requires Python 3 and dpkg-deb."""
from pathlib import Path
import bz2, gzip, hashlib, html, json, lzma, re, shutil, subprocess
from datetime import datetime, timezone
from email.utils import format_datetime
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '_site'
URL = 'https://brooktrout12.github.io/brooktrout12tweaks/'
GITHUB = 'https://github.com/Brooktrout12/brooktrout12tweaks'

def parse(text):
    fields = {}; key = None
    for line in text.splitlines():
        if line.startswith((' ', '\t')):
            if key is None: raise ValueError('Orphan continuation')
            fields[key] += '\n' + line
        elif line:
            key, sep, value = line.partition(':')
            if not sep or key in fields: raise ValueError('Invalid or duplicate field')
            fields[key] = value.lstrip()
    return fields

def digest(b, algorithm='sha256'):
    return hashlib.new(algorithm,b).hexdigest()

def page(title, body):
    return '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>'''+html.escape(title)+'''</title><style>body{font:16px/1.6 system-ui,sans-serif;background:#111722;color:#edf3fa;max-width:980px;margin:auto;padding:32px 20px}a{color:#8dcaff}h1{line-height:1.15;font-size:2.4rem}small,.muted{color:#b1bfd0}.card{padding:22px;background:#1c2737;border:1px solid #344358;border-radius:16px;margin:16px 0}code{overflow-wrap:anywhere}table{width:100%;border-collapse:collapse}td,th{text-align:left;padding:12px 8px;border-bottom:1px solid #344358}nav a{display:inline-block;padding:10px 16px;margin:8px 8px 8px 0;background:#263c56;border-radius:8px}.tag{color:#b6dca5}footer{margin-top:36px}</style>'''+body+'</html>\n'

def main():
    # Catalog metadata is optional; DEBs are the package inventory.
    try:
        catalog=json.loads((ROOT/'catalog.json').read_text())
        if not isinstance(catalog, dict): catalog={}
    except (OSError, ValueError) as exc:
        print('Optional catalog unavailable; using package metadata:', exc)
        catalog={}
    if OUT.exists(): shutil.rmtree(OUT)
    (OUT/'depictions').mkdir(parents=True)
    stanzas=[]; manifest=[]; identities=set(); architectures=set(); cards=[]
    for p in sorted((ROOT/'debs').rglob('*.deb')):
        if p.is_symlink(): raise ValueError('Symlink package')
        rel=p.relative_to(ROOT).as_posix()
        if re.search(r'[^A-Za-z0-9_./+~%-]', rel): raise ValueError('Use URL-safe DEB filenames: '+rel)
        fields=parse(subprocess.check_output(['dpkg-deb','--field',str(p)],text=True))
        for required in ['Package','Version','Architecture','Description']:
            if not fields.get(required): raise ValueError('Missing '+required+' in '+rel)
        ident=tuple(fields[k] for k in ('Package','Version','Architecture'))
        if ident in identities: raise ValueError('Duplicate package/version/architecture: '+str(ident))
        identities.add(ident); architecture=fields['Architecture']; architectures.add(architecture)
        if architecture not in ('iphoneos-arm64','iphoneos-arm','all'): raise ValueError('Unexpected architecture '+architecture)
        package=fields['Package']
        if not re.fullmatch(r'[a-z0-9][a-z0-9+.-]+',package): raise ValueError('Invalid package ID')
        meta=catalog.get(package, {})
        if not isinstance(meta, dict): meta={}
        source_path=meta.get('source')
        source=None
        if isinstance(source_path, str):
            candidate=ROOT/source_path
            if candidate.exists() and candidate.resolve().is_relative_to((ROOT/'sources').resolve()):
                source=source_path
        status=meta.get('status', '')
        if not isinstance(status, str): status=''
        meta={'source': source, 'status': status}
        b=p.read_bytes(); destination=OUT/rel;destination.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,destination)
        depiction='depictions/'+package+'-'+architecture+'-'+digest(fields['Version'].encode())[:16]+'.html'
        fields.update({'Filename':rel,'Size':str(len(b)),'MD5sum':digest(b,'md5'),'SHA1':digest(b,'sha1'),'SHA256':digest(b),'SHA512':digest(b,'sha512'),'Depiction':URL+depiction})
        stanzas.append('\n'.join(k+': '+v for k,v in fields.items())+'\n\n')
        name=fields.get('Name',package);version=fields['Version']; desc=fields['Description'].split('\n')[0]
        srcurl=GITHUB+'/tree/main/'+quote(meta['source'],safe='/') if meta['source'] else GITHUB
        source_label='Source &amp; build notes' if meta['source'] else 'GitHub repository'
        body='<p><a href="../">← All tweaks</a></p><h1>'+html.escape(name)+'</h1><p>'+html.escape(desc)+'</p><div class="card"><p>Version '+html.escape(version)+' · '+html.escape(architecture)+'</p><p>'+html.escape(meta['status'])+'</p><p>Dependencies: '+html.escape(fields.get('Depends','None declared'))+'</p></div><nav><a href="'+srcurl+'">'+source_label+'</a><a href="../'+rel+'">Download DEB</a></nav><p class="muted">Package ID: '+html.escape(package)+'</p>'
        (OUT/depiction).write_text(page(name,body))
        cards.append('<tr><td><a href="'+depiction+'">'+html.escape(name)+'</a></td><td>'+html.escape(version)+'</td><td>'+('Rootless' if architecture=='iphoneos-arm64' else architecture)+'</td></tr>')
        manifest.append({'package':package,'version':version,'architecture':architecture,'filename':rel,'size':len(b),'sha256':digest(b),'source':meta['source'],'status':meta['status']})
    # Publishing an empty index also removes the last deleted package.
    if not architectures: architectures.update(('iphoneos-arm', 'iphoneos-arm64'))
    data=''.join(stanzas).encode()
    (OUT/'Packages').write_bytes(data)
    (OUT/'Packages.gz').write_bytes(gzip.compress(data,mtime=0))
    (OUT/'Packages.bz2').write_bytes(bz2.compress(data))
    (OUT/'Packages.xz').write_bytes(lzma.compress(data))
    release=['Origin: Brooktrout12','Label: Brooktrout12 Tweaks','Suite: stable','Version: 1.0','Codename: brooktrout12','Architectures: '+' '.join(sorted(architectures)),'Components: main','Description: Brooktrout12 open-source iOS jailbreak tweaks','Date: '+format_datetime(datetime.now(timezone.utc),usegmt=True)]
    for label,algo in [('MD5Sum','md5'),('SHA256','sha256'),('SHA512','sha512')]:
        release.append(label+':')
        for n in ['Packages','Packages.gz','Packages.bz2','Packages.xz']:
            b=(OUT/n).read_bytes();release.append(' '+digest(b,algo)+' '+str(len(b))+' '+n)
    (OUT/'Release').write_text('\n'.join(release)+'\n')
    (OUT/'.nojekyll').touch()
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (OUT/'SHA256SUMS').write_text(''.join(m['sha256']+'  '+m['filename']+'\n' for m in manifest))
    links='<nav><a href="sileo://source/'+URL+'">Add to Sileo</a><a href="zbra://sources/add/'+URL+'">Add to Zebra</a><a href="'+GITHUB+'">View source</a></nav>'
    body='<p class="tag">Brooktrout12 · Open-source tweaks</p><h1>Make iOS your own.</h1><p>Install tweaks and receive updates through your jailbreak package manager.</p><div class="card"><strong>Repository URL</strong><p><code>'+URL+'</code></p>'+links+'</div><h2>Available tweaks</h2><p class="muted">Compatibility requirements and test status appear on each package page.</p><table><thead><tr><th>Tweak</th><th>Version</th><th>Environment</th></tr></thead><tbody>'+''.join(cards)+'</tbody></table><footer><a href="'+GITHUB+'/blob/main/LICENSING.md">Licenses &amp; credits</a> · <a href="'+GITHUB+'/issues">Report an issue</a></footer>'
    (OUT/'index.html').write_text(page('Brooktrout12 Tweaks',body))
    print('Built',len(manifest),'packages into',OUT)

if __name__=='__main__':
    import runpy
    runpy.run_path(str(ROOT/'scripts/import_sources_2026_10_17.py'), run_name='__main__')
    main()
