"""Align the exact displayed words with Wav2Vec2 CTC acoustic probabilities.

Offline model: onnx-community/wav2vec2-base-960h-ONNX, model_quantized.onnx
Requires numpy, onnxruntime and num2words. The model is a build-time tool only.
Publisher paragraph times reset the acoustic alignment at each paragraph.
"""
import argparse
import json
import pathlib
import re
import subprocess
import unicodedata
import urllib.request

import numpy as np
import onnxruntime as ort
from num2words import num2words


def normal(token, recognized):
    token = unicodedata.normalize('NFKD', token).replace('’', "'").lower()
    if token.startswith('(') and token.strip('().,;:!?') in {'iss', 'km/h', 'bpm'}:
        return []
    token = token.replace('km/h', 'kilometers per hour').replace('%', ' percent')
    token = re.sub(r'(?<=\d),(?=\d)', '', token)

    def number(match):
        value = match[0]
        options = [num2words(value)]
        if re.fullmatch(r'(19|20)\d{2}', value):
            options.insert(0, num2words(int(value), to='year'))
        options += [o.replace(' and ', ' ') for o in options]
        for candidate in options:
            key = '|'.join(re.findall('[a-z]+', candidate)).upper()
            if key in recognized:
                return candidate
        return options[0]

    token = re.sub(r'\d+(?:\.\d+)?', number, token)
    token = re.sub(r'\biss\b', 'i s s', token)
    token = re.sub(r'\bbpm\b', 'b p m', token)
    return re.findall(r"[a-z]+(?:'[a-z]+)?", token)


def align(text, samples, session, vocabulary):
    values = samples.astype(np.float32) / 32768
    values = (values - values.mean()) / np.sqrt(values.var() + 1e-7)
    logits = session.run(None, {'input_values': values[None]})[0][0]
    maximum = logits.max(axis=1, keepdims=True)
    logp = logits - maximum - np.log(np.exp(logits - maximum).sum(axis=1, keepdims=True))
    inverse = {v: k for k, v in vocabulary.items()}
    greedy = []
    previous = None
    for index in logits.argmax(axis=1):
        if index != previous and index != 0:
            greedy.append(inverse[int(index)])
        previous = index
    recognized = ''.join(greedy)
    tokens, owners, spans = [], [], []
    for match in re.finditer(r'\S+', text):
        parts = normal(match[0], recognized)
        spans.append((len(text[:match.start()].encode('utf-16-le')) // 2,
                      len(match[0].encode('utf-16-le')) // 2))
        if not parts:
            continue
        if tokens:
            tokens.append(vocabulary['|'])
            owners.append(None)
        for i, part in enumerate(parts):
            if i:
                tokens.append(vocabulary['|'])
                owners.append(None)
            for character in part.upper():
                tokens.append(vocabulary[character])
                owners.append(len(spans) - 1)

    # CTC Viterbi: blank / character / blank ...; every transcript character
    # must be visited, while blanks absorb silence rather than shifting words.
    states = np.zeros(len(tokens) * 2 + 1, dtype=np.int64)
    states[1::2] = tokens
    can_skip = np.zeros(len(states), dtype=bool)
    can_skip[2:] = (states[2:] != 0) & (states[2:] != states[:-2])
    costs = np.full(len(states), -np.inf, dtype=np.float32)
    costs[0] = 0
    back = np.empty((len(logp), len(states)), dtype=np.uint8)
    for frame, probabilities in enumerate(logp):
        advance = np.r_[-np.inf, costs[:-1]]
        skip = np.r_[-np.inf, -np.inf, costs[:-2]]
        skip[~can_skip] = -np.inf
        choices = np.stack([costs, advance, skip])
        back[frame] = choices.argmax(axis=0)
        costs = choices.max(axis=0) + probabilities[states]
    state = len(states) - 1 if costs[-1] >= costs[-2] else len(states) - 2
    if not np.isfinite(costs[state]):
        raise ValueError('Acoustic alignment did not reach the end of the transcript')
    path = np.empty(len(logp), dtype=np.int64)
    for frame in range(len(logp) - 1, -1, -1):
        path[frame] = state
        state -= int(back[frame, state])
    seconds_per_frame = len(samples) / 16000 / len(logp)
    grouped = {}
    for frame, state in enumerate(path):
        if state % 2 == 0:
            continue
        owner = owners[(state - 1) // 2]
        if owner is None:
            continue
        if owner not in grouped:
            grouped[owner] = dict(start=frame * seconds_per_frame,
                                  end=(frame + 1) * seconds_per_frame,
                                  location=spans[owner][0], length=spans[owner][1])
        else:
            grouped[owner]['end'] = (frame + 1) * seconds_per_frame
    return list(grouped.values())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--model', type=pathlib.Path, required=True)
    parser.add_argument('--vocab', type=pathlib.Path, required=True)
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parents[1] / 'Main/Listening/Resources'
    tracks = json.loads((root / 'tracks.json').read_text(encoding='utf-8-sig'))
    sources = json.loads((root / 'audio-sources.json').read_text())
    vocabulary = json.loads(args.vocab.read_text())
    options = ort.SessionOptions()
    options.intra_op_num_threads = 4
    session = ort.InferenceSession(str(args.model), options, providers=['CPUExecutionProvider'])
    result = {}
    for track, source in zip(tracks, sources):
        photo = track['id']
        with urllib.request.urlopen(source['script'], timeout=30) as response:
            paragraphs = json.load(response)['children']
        full_text = '\n\n'.join(track['sections'])
        spans = list(re.finditer(r'\S(?:.*?\S)?(?=(?:\r?\n){2}|$)', full_text, re.S))
        raw = subprocess.check_output(['ffmpeg', '-v', 'error', '-i', str(root / 'Audio' / f'photo-{photo}-full.mp3'),
                                       '-f', 's16le', '-ar', '16000', '-ac', '1', '-'])
        samples = np.frombuffer(raw, dtype='<i2')
        full_words = []
        for i, (span, paragraph) in enumerate(zip(spans, paragraphs)):
            start = paragraph['position'] / 1000
            end = paragraphs[i+1]['position'] / 1000 if i+1 < len(paragraphs) else len(samples)/16000
            words = align(span[0], samples[round(start*16000):round(end*16000)], session, vocabulary)
            offset = len(full_text[:span.start()].encode('utf-16-le')) // 2
            full_words.extend(dict(start=round(w['start']+start, 3), end=round(w['end']+start, 3),
                                   location=w['location']+offset, length=w['length']) for w in words)
            print(f'Photo {photo}, paragraph {i+1}: aligned {len(words)} words', flush=True)
        result[f'photo-{photo}-full'] = full_words
        offset = 0
        for i, text in enumerate(track['sections']):
            length = len(text.encode('utf-16-le')) // 2
            start = source['chapterStarts'][i]
            result[f'photo-{photo}-chapter-{i+1}'] = [
                dict(start=round(max(0,w['start']-start),3), end=round(w['end']-start,3),
                     location=w['location']-offset, length=w['length'])
                for w in full_words if offset <= w['location'] < offset+length]
            offset += length+2
        source['wordAlignment'] = 'Wav2Vec2 CTC Viterbi; publisher paragraph anchors'
    (root / 'word-timings.json').write_text(json.dumps(result, separators=(',',':')), encoding='utf-8')
    (root / 'audio-sources.json').write_text(json.dumps(sources,ensure_ascii=False,indent=2), encoding='utf-8')
    print('Rebuilt all 15 word timelines from CTC acoustic alignment.', flush=True)


if __name__ == '__main__':
    main()
