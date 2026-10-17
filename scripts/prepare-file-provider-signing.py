"""Align File Provider metadata with AltForge's authorized app group locally.

Only certificate file names are examined; private key contents are never read.
The resulting IPA must be re-signed by AltForge before installation.
"""
import os
import plistlib
import re
import sys
import tempfile
import zipfile
from pathlib import Path


def main():
    ipa = Path(sys.argv[1]).resolve(strict=True)
    approved = (Path(os.environ['LOCALAPPDATA']) / 'AltServerDirectIPA' /
                'Remote' / 'ApprovedIPAs').resolve(strict=True)
    if ipa.parent != approved or ipa.suffix.lower() != '.ipa':
        raise SystemExit('Only an IPA in the local AltForge approved folder is supported.')
    certificates = Path(os.environ['PROGRAMDATA']) / 'AltServer' / 'Certificates'
    teams = {p.stem for p in certificates.glob('*.p12')
             if re.fullmatch(r'[A-Z0-9]{10}', p.stem)}
    if len(teams) != 1:
        raise SystemExit('A single cached signing team is required; no IPA was changed.')
    original = 'group.com.kakikukeko.main.pcfilebridge'
    group = original + '.' + next(iter(teams))
    paths = ['Payload/main.app/Info.plist',
             'Payload/main.app/PlugIns/PCFileBridgeFileProvider.appex/Info.plist']
    with zipfile.ZipFile(ipa) as source:
        replacements = {}
        for path in paths:
            info = plistlib.loads(source.read(path))
            configured = info.get('PCFileBridgeAppGroup')
            if configured not in (original, group):
                raise SystemExit('Unexpected app group; no IPA was changed.')
            info['PCFileBridgeAppGroup'] = group
            if 'NSExtension' in info:
                info['NSExtension']['NSExtensionFileProviderDocumentGroup'] = group
            replacements[path] = plistlib.dumps(info, fmt=plistlib.FMT_XML)
        handle, temporary = tempfile.mkstemp(prefix='bridge-signing-', suffix='.ipa', dir=approved)
        os.close(handle)
        try:
            with zipfile.ZipFile(temporary, 'w') as target:
                for entry in source.infolist():
                    target.writestr(entry, replacements.get(entry.filename, source.read(entry)))
            source.close()
            os.replace(temporary, ipa)
        finally:
            Path(temporary).unlink(missing_ok=True)
    print('File Provider metadata aligned with the cached AltForge signing team.')


if __name__ == '__main__':
    main()
