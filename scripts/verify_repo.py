#!/usr/bin/env python3
"""Independent checks of generated indexes, compressed copies and DEB bytes."""
from pathlib import Path
import bz2,gzip,hashlib,json,lzma,subprocess
from build_repo import ROOT, OUT, parse

def main():
    raw=(OUT/'Packages').read_bytes()
    for suffix,unpack in [('gz',gzip.decompress),('bz2',bz2.decompress),('xz',lzma.decompress)]:
        assert unpack((OUT/('Packages.'+suffix)).read_bytes())==raw
    records=[parse(s) for s in raw.decode().strip().split('\n\n') if s.strip()]
    assert len(records)==len(list((ROOT/'debs').rglob('*.deb')))
    for record in records:
        path=OUT/record['Filename'];b=path.read_bytes()
        assert path.resolve().is_relative_to(OUT.resolve())
        assert b==(ROOT/record['Filename']).read_bytes()
        assert len(b)==int(record['Size'])
        for field,algo in [('MD5sum','md5'),('SHA1','sha1'),('SHA256','sha256'),('SHA512','sha512')]:
            assert hashlib.new(algo,b).hexdigest()==record[field]
        original=parse(subprocess.check_output(['dpkg-deb','--field',str(path)],text=True))
        for field in ['Package','Version','Architecture','Depends']:
            assert original.get(field)==record.get(field)
        assert (OUT/'depictions'/record['Depiction'].rsplit('/',1)[-1]).is_file()
    release=parse((OUT/'Release').read_text())
    for field,algo in [('MD5Sum','md5'),('SHA256','sha256'),('SHA512','sha512')]:
        for entry in release[field].splitlines():
            if not entry.strip():continue
            checksum,size,name=entry.split();b=(OUT/name).read_bytes()
            assert int(size)==len(b) and hashlib.new(algo,b).hexdigest()==checksum
    assert len(json.loads((OUT/'manifest.json').read_text()))==len(records)
    print('PASS:',len(records),'packages; original DEBs unchanged; indexes, compressed indexes, dependency fields and release checksums verified.')
if __name__=='__main__':main()
