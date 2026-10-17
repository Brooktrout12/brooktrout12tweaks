"""One-time expansion of the existing, hash-checked source uploads."""
from pathlib import Path, PurePosixPath
import hashlib, io, json, shutil, stat, zipfile

ROOT = Path(__file__).resolve().parents[1]
SPECS = [
    ('BlurSleep', '1.2.0', '7f4a25f30b2177acb9485a78c4e0acc0a7bac60998a56e3bbdab0a56c7e4a595'),
    ('CCNoRecent', '1.0.0', 'd39bc7b932a90783168640dd49da9ef1d08bd386c104fcf759118fb093432e0f'),
]

def main():
    for name, version, expected in SPECS:
        archive = ROOT/'sources'/f'{name}_{version}_DEB_and_Source.zip'
        payload = archive.read_bytes()
        assert hashlib.sha256(payload).hexdigest() == expected, archive
        destination = ROOT/'sources'/name
        prefix = f'{name}_{version}/Source/'
        with zipfile.ZipFile(io.BytesIO(payload)) as z:
            files = []
            for entry in z.infolist():
                if not entry.filename.startswith(prefix) or entry.is_dir():
                    continue
                rel = PurePosixPath(entry.filename.removeprefix(prefix))
                assert rel.parts and not rel.is_absolute() and '..' not in rel.parts
                assert '.git' not in rel.parts and not stat.S_ISLNK(entry.external_attr >> 16)
                files.append((rel, z.read(entry)))
            assert files
            # Validate each archived source byte against its release manifest.
            checksums = z.read(f'{name}_{version}/SOURCE_SHA256SUMS').decode()
            expected_sources = {}
            for line in checksums.splitlines():
                checksum, path = line.split(None, 1)
                assert path.startswith('Source/')
                expected_sources[path.removeprefix('Source/')] = checksum
            assert {p.as_posix() for p, _ in files} == set(expected_sources)
            for rel, data in files:
                assert hashlib.sha256(data).hexdigest() == expected_sources[rel.as_posix()]
            if destination.exists():
                shutil.rmtree(destination)
            for rel, data in files:
                target = destination/Path(*rel.parts)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
                target.chmod(0o755 if target.suffix == '.sh' else 0o644)
            shutil.copy2(ROOT/'LICENSE', destination/'LICENSE')
            (destination/'RELEASE-NOTES.md').write_bytes(z.read(f'{name}_{version}/README.md'))
        archive.unlink()

    notes_file = ROOT/'scripts/publication-notes.json'
    for rel, text in json.loads(notes_file.read_text()).items():
        target = ROOT/rel
        assert target.resolve().is_relative_to((ROOT/'sources').resolve())
        if text is None:
            target.unlink()
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
    notes_file.unlink()

    builder = ROOT/'scripts/build_repo.py'
    injected = "if __name__=='__main__':\n    import runpy\n    runpy.run_path(str(ROOT/'scripts/import_sources_2026_10_17.py'), run_name='__main__')\n    main()"
    content = builder.read_text()
    assert content.count(injected) == 1
    builder.write_text(content.replace(injected, "if __name__=='__main__':main()"))
    Path(__file__).unlink()
    print('Expanded and verified BlurSleep and CCNoRecent sources; one-time importer removed.')

if __name__ == '__main__':
    main()
