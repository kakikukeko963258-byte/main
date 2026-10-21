"""Reproduce the bundled Kanto railway snapshot from a pinned Mini Tokyo 3D revision."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import urllib.request

REVISION = '68314fe92773aa4691075b79243f2010fc8e2836'
BASE = f'https://raw.githubusercontent.com/nagix/mini-tokyo-3d/{REVISION}/'
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'Main/RailRide/Resources'

def fetch(path):
    with urllib.request.urlopen(BASE + path, timeout=90) as response:
        return response.read()

def load(path):
    return json.loads(fetch(path))

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    railways = load('data/railways.json')
    stations = load('data/stations.json')
    station_lines = {s: r['id'] for r in railways for s in r.get('stations', [])}
    stations = [dict(s, railway=s.get('railway', station_lines.get(s['id'], s['id'].rsplit('.', 1)[0])))
                for s in stations if len(s.get('coord', [])) >= 2]
    types = {x['id']: x['title'].get('ja', x['id']) for x in load('data/train-types.json')}
    shapes = {x['id']: [s['coords'] for s in x['sublines'] if len(s.get('coords', [])) > 1]
              for x in load('data/coordinates.json')['railways']}
    # Directory listing comes from GitHub's public tree, pinned to the same commit.
    with urllib.request.urlopen(f'https://api.github.com/repos/nagix/mini-tokyo-3d/git/trees/{REVISION}?recursive=1') as response:
        files = [x['path'] for x in json.load(response)['tree']
                 if x['path'].startswith('data/train-timetables/') and x['path'].endswith('.json')]
    known = {s['id'] for s in stations}
    patterns = {}
    def read_patterns(path):
        return load(path)
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        for trains in pool.map(read_patterns, files):
            for train in trains:
                stops = [s['s'] for s in train.get('tt', []) if s.get('s') in known]
                if len(stops) < 2 or not train.get('y'):
                    continue
                signature = (train['r'], train['y'], tuple(stops))
                patterns[signature] = {'line': train['r'], 'type': types.get(train['y'], train['y']), 'stops': stops}
    lines = [{'id': r['id'], 'name': r['title'].get('ja', r['id']),
              'color': r.get('color', '#42A5F5'), 'stations': r.get('stations', []),
              'paths': shapes.get(r['id'], [])} for r in railways if len(r.get('stations', [])) > 1]
    patterns = [dict(p, id=hashlib.sha256(repr(k).encode()).hexdigest()[:16]) for k, p in sorted(patterns.items())]
    result = {'revision': REVISION, 'date': '2026-10-21', 'lines': lines,
              'stations': [{'id': s['id'], 'name': s['title'].get('ja', s['id']),
                            'line': s['railway'], 'lon': s['coord'][0], 'lat': s['coord'][1]} for s in stations],
              'groups': [[s for subgroup in group for s in subgroup] for group in load('data/station-groups.json')],
              'patterns': patterns}
    (OUT / 'kanto-rail.json').write_text(json.dumps(result, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    (OUT / 'MiniTokyo3D-LICENSE.txt').write_bytes(fetch('LICENSE'))
    print(f"{len(lines)} lines, {len(stations)} station entries, {len(patterns)} stopping patterns; {len(files)} timetable files")

if __name__ == '__main__':
    main()
