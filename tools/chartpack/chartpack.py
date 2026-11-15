#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
chartpack.py - Meteoric Engine chart packer (.json <-> .mec)

.mec is a binary container: 64-byte LE header + uncompressed 8KB head preview
+ a compressed payload. ALL THREE codecs are byte-lossless: decompressed bytes
are identical to the source .json, so unpack restores the file exactly and the
engine's byte-level chart scanners keep working unchanged.

Codecs (v1/v2 all readable by the current engine):
  deflate  v1  single zlib DEFLATE stream (wbits=15). Fastest, broadest compat.
  lzma     v2  16MB independent LZMA1 blocks (lime native decoder). ~1.1% ratio.
  struct   v2  columnar structured codec, the default. Note tuples are pulled
               out of the JSON into dictionaries + varint index streams, then
               each of 7 streams is LZMA1-compressed. ~0.14% ratio on dense
               overcharts (648MB -> ~0.9MB). Decoder rebuilds tuple text from
               the original byte dictionaries, so it stays byte-lossless.

Zero third-party dependencies. Python 3.8+. 4 MiB streaming chunks.

Commands:
  pack      compress chart .json files into .mec
  unpack    restore a .mec into the original .json bytes
  info      print container header and compression ratio
  verify    stream-decompress, check CRC32/size, optionally byte-compare
  scancheck prove a .mec scans into identical note clusters as its .json (hxcpp)
  selftest  end-to-end round trip over all codecs + hxcpp decoder check

Examples:
  python3 tools/chartpack/chartpack.py pack mods/My-Mod/data/
  python3 tools/chartpack/chartpack.py pack song/hard.json --codec lzma
  python3 tools/chartpack/chartpack.py pack mods/My-Mod --dry-run
  python3 tools/chartpack/chartpack.py verify song/hard.mec --against song/hard.json
  python3 tools/chartpack/chartpack.py unpack song/hard.mec --force
  python3 tools/chartpack/chartpack.py scancheck song/hard.mec song/hard.json
  python3 tools/chartpack/chartpack.py selftest

Directory mode collects .json files directly inside <root>/**/data/<song>/
and <root>/**/charts/<song>/ only. Metadata such as mod.json / pack.json /
characters/*.json is never touched. modchart.json is skipped by default.

Priority in the engine: .mec wins over a same-stem .json in the same folder.
Keep both files until the packed chart has been verified in game.
"""

import argparse
import lzma
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib

MAGIC = b'MEC1'
VERSION_V1 = 1
VERSION_V2 = 2
HEADER_SIZE = 64
HEAD_PREVIEW = 8192
CHUNK = 4 * 1024 * 1024
OUT_CHUNK = 256 * 1024
FLAG_CRC32 = 1
CODEC_DEFLATE = 0
CODEC_LZMA = 1
CODEC_STRUCT = 2
CODEC_IDS = {'deflate': CODEC_DEFLATE, 'lzma': CODEC_LZMA, 'struct': CODEC_STRUCT}
CODEC_NAMES = {v: k for k, v in CODEC_IDS.items()}
DEFAULT_CODEC = 'struct'
BLOCK_SIZE = 16 * 1024 * 1024
LZMA_PRESET = 6
STRUCT_STREAMS = 7
STRUCT_MARK = b'\x00'
# [time, lane, anything...] - lane must be a plain integer, so events like
# [0, [["Change Character", ...]]] are never mistaken for a note.
NOTE_PAT = re.compile(rb'\[(-?\d+(?:\.\d+)?),(-?\d+)([^\]]*)\]')

EXCLUDE_NAMES = {'modchart.json'}
CHART_DIR_NAMES = ('data', 'charts')
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
CODEC_SRC = os.path.join(REPO_ROOT, 'source', 'backend', 'ChartCodec.hx')
SELFTEST_SRC = os.path.join(os.path.dirname(__file__), 'ChartCodecSelfTest.hx')
NDLL_SRC = os.path.join(REPO_ROOT, 'tools', 'lime.ndll.wallclock')


class PackError(Exception):
    pass


# ---------------------------------------------------------------------------
# Container header
# ---------------------------------------------------------------------------

def _header_bytes(head_len, raw_size, comp_size, crc, version, flags, block_size=0):
    if head_len > 0xFFFF:
        raise PackError('head preview too large')
    return (MAGIC
            + struct.pack('<BB', version, flags)
            + struct.pack('<H', head_len)
            + struct.pack('<Q', raw_size)
            + struct.pack('<Q', comp_size)
            + struct.pack('<I', crc & 0xFFFFFFFF)
            + struct.pack('<I', block_size)
            + b'\0' * 32)


def read_header(path):
    size = os.path.getsize(path)
    with open(path, 'rb') as f:
        raw = f.read(HEADER_SIZE)
    if len(raw) < HEADER_SIZE or raw[:4] != MAGIC:
        raise PackError('%s: not a .mec file (bad magic)' % path)
    version, flags = struct.unpack_from('<BB', raw, 4)
    if version not in (VERSION_V1, VERSION_V2):
        raise PackError('%s: unsupported version %d' % (path, version))
    head_len, = struct.unpack_from('<H', raw, 6)
    raw_size, comp_size, crc = struct.unpack_from('<QQI', raw, 8)
    block_size, = struct.unpack_from('<I', raw, 28)
    data_offset = HEADER_SIZE + head_len
    codec = CODEC_DEFLATE if version == VERSION_V1 else ((flags >> 1) & 3)
    if codec not in CODEC_NAMES:
        raise PackError('%s: unsupported codec %d' % (path, codec))
    if head_len > HEAD_PREVIEW:
        raise PackError('%s: head preview too large (%d)' % (path, head_len))
    if size != data_offset + comp_size:
        raise PackError('%s: truncated file (expected %d bytes, got %d)'
                        % (path, data_offset + comp_size, size))
    return {
        'version': version, 'flags': flags, 'codec': codec,
        'codec_name': CODEC_NAMES[codec], 'head_len': head_len,
        'raw_size': raw_size, 'comp_size': comp_size, 'crc': crc,
        'block_size': block_size, 'data_offset': data_offset,
        'file_size': size,
    }


# ---------------------------------------------------------------------------
# LZMA1 frames (lime-compatible: 5B props + 8B LE uncompressed size + raw data)
# ---------------------------------------------------------------------------

def lzma_frame(data):
    alone = lzma.compress(data, format=lzma.FORMAT_ALONE, preset=LZMA_PRESET)
    return alone[:5] + struct.pack('<Q', len(data)) + alone[13:]


def lzma_frame_decode(frame, where):
    if len(frame) < 13:
        raise PackError('%s: LZMA frame too short' % where)
    props = frame[:5]
    declared, = struct.unpack_from('<Q', frame, 5)
    dict_size, = struct.unpack_from('<I', props, 1)
    v = props[0]
    lc, lp, pb = v % 9, (v // 9) % 5, v // 45
    try:
        dec = lzma.LZMADecompressor(format=lzma.FORMAT_RAW, filters=[
            {'id': lzma.FILTER_LZMA1, 'dict_size': dict_size,
             'lc': lc, 'lp': lp, 'pb': pb}])
        out = dec.decompress(frame[13:], max_length=declared)
    except lzma.LZMAError as e:
        raise PackError('%s: LZMA decode failed: %s' % (where, e))
    if len(out) != declared:
        raise PackError('%s: LZMA size mismatch (%d != %d)' % (where, len(out), declared))
    return out


def _read_frame(f, where):
    hdr = f.read(4)
    if len(hdr) != 4:
        raise PackError('%s: truncated frame length' % where)
    flen, = struct.unpack('<I', hdr)
    if flen < 13 or flen > 512 * 1024 * 1024:
        raise PackError('%s: bad frame length %d' % (where, flen))
    frame = f.read(flen)
    if len(frame) != flen:
        raise PackError('%s: truncated LZMA frame' % where)
    return 4 + flen, lzma_frame_decode(frame, where)


# ---------------------------------------------------------------------------
# Decode
# ---------------------------------------------------------------------------

def _varint(n):
    out = bytearray()
    while n >= 0x80:
        out.append((n & 0x7F) | 0x80)
        n >>= 7
    out.append(n)
    return bytes(out)


def _zigzag(n):
    # time indexes can go backwards between sections; LEB128 needs non-negative
    return n << 1 if n >= 0 else ((-n << 1) - 1)


def _zigzag_decode(v):
    return (v >> 1) if not (v & 1) else -((v + 1) >> 1)


def _var_reader(data):
    pos = [0]

    def nxt(where):
        v = 0
        shift = 0
        while True:
            if pos[0] >= len(data):
                raise PackError('%s: varint stream exhausted' % where)
            c = data[pos[0]]
            pos[0] += 1
            v |= (c & 127) << shift
            if not (c & 128):
                return v
            shift += 7

    return nxt


def _split_dict(blob, where):
    if not blob.endswith(b'\n'):
        raise PackError('%s: dictionary stream is not newline-terminated' % where)
    return blob[:-1].split(b'\n')


def _inflate_deflate(path, h, emit):
    dec = zlib.decompressobj(15)
    with open(path, 'rb') as f:
        f.seek(h['data_offset'])
        left = h['comp_size']
        while left > 0:
            data = f.read(min(CHUNK, left))
            if not data:
                raise PackError('%s: unexpected end of deflate stream' % path)
            left -= len(data)
            while data:
                out = dec.decompress(data, OUT_CHUNK)
                if out:
                    emit(out)
                data = dec.unconsumed_tail
                if dec.eof:
                    data = b''
                elif not out and data:
                    raise PackError('%s: inflate made no progress' % path)
            if dec.eof:
                break
        tail = dec.flush()
        if tail:
            emit(tail)
    if not dec.eof:
        raise PackError('%s: deflate stream is truncated' % path)


def _inflate_lzma_blocks(path, h, emit):
    with open(path, 'rb') as f:
        f.seek(h['data_offset'])
        left = h['comp_size']
        while left > 0:
            used, block = _read_frame(f, path)
            left -= used
            if left < 0:
                raise PackError('%s: LZMA frame overruns payload' % path)
            for i in range(0, len(block), OUT_CHUNK):
                emit(block[i:i + OUT_CHUNK])


def _inflate_struct(path, h, emit):
    with open(path, 'rb') as f:
        f.seek(h['data_offset'])
        left = h['comp_size']
        streams = []
        for _ in range(STRUCT_STREAMS):
            used, blob = _read_frame(f, path)
            left -= used
            streams.append(blob)
        if left != 0 or f.read(1):
            raise PackError('%s: structured payload size mismatch' % path)

    skeleton, times, rests, col_dict, tdelta, cols, restidx = streams
    times = _split_dict(times, path)
    rests = _split_dict(rests, path)
    col_dict = _split_dict(col_dict, path)
    rt = _var_reader(tdelta)
    rc = _var_reader(cols)
    rr = _var_reader(restidx)

    out = bytearray()
    prev_t = 0
    pos = 0
    slen = len(skeleton)
    while pos < slen:
        idx = skeleton.find(STRUCT_MARK, pos)
        end = slen if idx < 0 else idx
        out += skeleton[pos:end]
        if idx >= 0:
            prev_t += _zigzag_decode(rt(path))
            ci = rc(path)
            ri = rr(path)
            try:
                out += (b'[' + times[prev_t] + b',' + col_dict[ci]
                        + rests[ri] + b']')
            except IndexError:
                raise PackError('%s: structured dictionary index out of range' % path)
            pos = idx + 1
        else:
            pos = slen
        if len(out) >= OUT_CHUNK:
            emit(bytes(out))
            out.clear()
    if out:
        emit(bytes(out))


def stream_inflate(path, sink):
    """Decode any .mec into sink(bytes). Returns header + measured values."""
    h = read_header(path)
    state = {'total': 0, 'crc': 0}

    def emit(buf):
        if not buf:
            return
        sink(buf)
        state['total'] += len(buf)
        state['crc'] = zlib.crc32(buf, state['crc'])

    if h['codec'] == CODEC_DEFLATE:
        _inflate_deflate(path, h, emit)
    elif h['codec'] == CODEC_LZMA:
        _inflate_lzma_blocks(path, h, emit)
    elif h['codec'] == CODEC_STRUCT:
        _inflate_struct(path, h, emit)
    else:
        raise PackError('%s: unsupported codec %d' % (path, h['codec']))

    total = state['total']
    crc = state['crc'] & 0xFFFFFFFF
    if total != h['raw_size']:
        raise PackError('%s: size mismatch (header %d, actual %d)'
                        % (path, h['raw_size'], total))
    if (h['flags'] & FLAG_CRC32) and crc != h['crc']:
        raise PackError('%s: CRC32 mismatch (header %08x, actual %08x)'
                        % (path, h['crc'], crc))
    h['measured_raw'] = total
    h['measured_crc'] = crc
    return h


def human(n):
    for unit in ('B', 'KiB', 'MiB', 'GiB'):
        if n < 1024 or unit == 'GiB':
            return '%.1f %s' % (n, unit)
        n /= 1024.0
    return str(n)


# ---------------------------------------------------------------------------
# Encode
# ---------------------------------------------------------------------------

def _encode_deflate(fi, fo, raw_size, level, quiet):
    co = zlib.compressobj(level, zlib.DEFLATED, 15)
    crc = 0
    comp_size = 0
    done = 0
    next_report = 256 * 1024 * 1024
    while True:
        chunk = fi.read(CHUNK)
        if not chunk:
            break
        crc = zlib.crc32(chunk, crc)
        out = co.compress(chunk)
        if out:
            fo.write(out)
            comp_size += len(out)
        done += len(chunk)
        if not quiet and done >= next_report:
            print('    %s / %s' % (human(done), human(raw_size)), flush=True)
            next_report = done + 256 * 1024 * 1024
    out = co.flush()
    if out:
        fo.write(out)
        comp_size += len(out)
    return comp_size, crc


def _encode_lzma_blocks(fi, fo, raw_size, block_size, quiet):
    crc = 0
    comp_size = 0
    done = 0
    while True:
        data = fi.read(block_size)
        if not data:
            break
        crc = zlib.crc32(data, crc)
        frame = lzma_frame(data)
        fo.write(struct.pack('<I', len(frame)))
        fo.write(frame)
        comp_size += 4 + len(frame)
        done += len(data)
        if not quiet:
            print('    %s / %s' % (human(done), human(raw_size)), flush=True)
    return comp_size, crc


def _encode_struct(fi, fo, raw_size, quiet):
    """Pull note tuples out of the JSON into 7 columnar streams."""
    t_dict, t_idx = [], {}
    r_dict, r_idx = [], {}
    c_dict, c_idx = [], {}
    skeleton = bytearray()
    tdelta = bytearray()
    cols = bytearray()
    restidx = bytearray()
    crc = 0
    done = 0
    carry = b''
    prev_t = 0
    next_report = 256 * 1024 * 1024
    while True:
        chunk = fi.read(CHUNK)
        if not chunk:
            break
        crc = zlib.crc32(chunk, crc)
        done += len(chunk)
        if not quiet and done >= next_report:
            print('    %s / %s' % (human(done), human(raw_size)), flush=True)
            next_report = done + 256 * 1024 * 1024
        data = carry + chunk
        last = 0
        pos = 0
        while True:
            m = NOTE_PAT.search(data, pos)
            if not m:
                break
            # Do not consume a match that may be incomplete at the chunk edge.
            if m.end() >= len(data) - 64:
                break
            skeleton += data[last:m.start()]
            skeleton += STRUCT_MARK
            t, col, rest = m.group(1), m.group(2), m.group(3)
            ti = t_idx.get(t)
            if ti is None:
                ti = len(t_dict); t_idx[t] = ti; t_dict.append(t)
            ci = c_idx.get(col)
            if ci is None:
                ci = len(c_dict); c_idx[col] = ci; c_dict.append(col)
            ri = r_idx.get(rest)
            if ri is None:
                ri = len(r_dict); r_idx[rest] = ri; r_dict.append(rest)
            tdelta += _varint(_zigzag(ti - prev_t))
            prev_t = ti
            cols += _varint(ci)
            restidx += _varint(ri)
            last = m.end()
            pos = m.end()
        # Keep only a small tail: long stretches without a note must not grow.
        keep = 64
        if len(data) - last > keep:
            skeleton += data[last:len(data) - keep]
            last = len(data) - keep
        carry = data[last:]
    skeleton += carry

    def dict_blob(items):
        return b'\n'.join(items) + b'\n' if items else b'\n'

    streams = [
        bytes(skeleton),
        dict_blob(t_dict),
        dict_blob(r_dict),
        dict_blob(c_dict),
        bytes(tdelta),
        bytes(cols),
        bytes(restidx),
    ]
    comp_size = 0
    for s in streams:
        frame = lzma_frame(s)
        fo.write(struct.pack('<I', len(frame)))
        fo.write(frame)
        comp_size += 4 + len(frame)
    return comp_size, crc


def pack_one(src, dst, level, force, quiet, delete_source, yes,
             min_size=4096, codec=DEFAULT_CODEC, block_size=BLOCK_SIZE):
    if not src.lower().endswith('.json'):
        raise PackError('%s: source must be a .json file' % src)
    if not os.path.isfile(src):
        raise PackError('%s: file not found' % src)
    if os.path.exists(dst) and not force:
        return 'skip (exists, use --force): %s' % dst
    raw_size = os.path.getsize(src)
    if raw_size == 0:
        raise PackError('%s: empty source file' % src)
    if raw_size < min_size:
        return 'skip (smaller than --min-size %d): %s' % (min_size, src)
    if codec not in CODEC_IDS:
        raise PackError('unknown codec: %s' % codec)
    cid = CODEC_IDS[codec]
    version = VERSION_V1 if cid == CODEC_DEFLATE else VERSION_V2
    flags = FLAG_CRC32 | (cid << 1)
    os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
    tmp = dst + '.tmp'
    try:
        with open(src, 'rb') as fi, open(tmp, 'w+b') as fo:
            head = fi.read(min(HEAD_PREVIEW, raw_size))
            fo.write(b'\0' * HEADER_SIZE)
            fo.write(head)
            fi.seek(0)
            if cid == CODEC_DEFLATE:
                comp_size, crc = _encode_deflate(fi, fo, raw_size, level, quiet)
            elif cid == CODEC_LZMA:
                comp_size, crc = _encode_lzma_blocks(fi, fo, raw_size, block_size, quiet)
            else:
                comp_size, crc = _encode_struct(fi, fo, raw_size, quiet)
            fo.flush()
            fo.seek(0)
            fo.write(_header_bytes(len(head), raw_size, comp_size, crc,
                                   version, flags, block_size))
        os.replace(tmp, dst)
    except BaseException:
        try:
            os.remove(tmp)
        except OSError:
            pass
        raise

    # Safety: prove the container round-trips byte-for-byte before touching anything.
    state = {'pos': 0, 'ok': True}
    with open(src, 'rb') as orig:
        def sink(buf):
            if not state['ok']:
                return
            if orig.read(len(buf)) != buf:
                state['ok'] = False
            state['pos'] += len(buf)
        stream_inflate(dst, sink)
    if not state['ok'] or state['pos'] != raw_size:
        os.remove(dst)
        raise PackError('%s: post-pack verification failed, output removed' % src)

    ratio = 100.0 * os.path.getsize(dst) / raw_size
    msg = 'pack  [%s] %s -> %s  %s => %s (%.3f%%)' % (
        codec, src, dst, human(raw_size), human(os.path.getsize(dst)), ratio)
    if delete_source:
        if not yes:
            msg += '  [source kept: --delete-source needs --yes]'
        else:
            os.remove(src)
            msg += '  [source deleted after verified round trip]'
    return msg


def collect_jsons(root):
    if os.path.isfile(root):
        return [root]
    if not os.path.isdir(root):
        raise PackError('%s: path not found' % root)
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        base = os.path.basename(dirpath)
        if base not in CHART_DIR_NAMES:
            continue
        for name in filenames:
            if name.lower().endswith('.json') and name.lower() not in EXCLUDE_NAMES:
                found.append(os.path.join(dirpath, name))
        for sub in dirnames:
            subpath = os.path.join(dirpath, sub)
            if not os.path.isdir(subpath):
                continue
            for name in sorted(os.listdir(subpath)):
                if name.lower().endswith('.json') and name.lower() not in EXCLUDE_NAMES:
                    found.append(os.path.join(subpath, name))
    return sorted(set(found))


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_pack(args):
    files = collect_jsons(args.path)
    if not files:
        raise PackError('no chart .json found under %s' % args.path)
    if args.dry_run:
        for f in files:
            print('would pack: %s' % f)
        print('%d file(s)' % len(files))
        return
    ok = 0
    for src in files:
        if args.output:
            rel = os.path.relpath(src, args.path if os.path.isdir(args.path) else os.path.dirname(src))
            dst = os.path.join(args.output, os.path.splitext(rel)[0] + '.mec')
        else:
            dst = os.path.splitext(src)[0] + '.mec'
        try:
            line = pack_one(src, dst, args.level, args.force, args.quiet,
                            args.delete_source, args.yes, args.min_size,
                            args.codec, args.block_size)
            print(line, flush=True)
            if not line.startswith('skip'):
                ok += 1
        except PackError as e:
            print('ERROR %s' % e, file=sys.stderr)
            if not args.keep_going:
                raise
    print('packed %d/%d file(s)' % (ok, len(files)))


def cmd_info(args):
    for path in args.path:
        h = read_header(path)
        ratio = 100.0 * h['file_size'] / h['raw_size']
        print('%s' % path)
        print('  version     %d   codec %s   flags 0x%02x'
              % (h['version'], h['codec_name'], h['flags']))
        print('  raw         %d bytes (%s)' % (h['raw_size'], human(h['raw_size'])))
        print('  compressed  %d bytes (%s)' % (h['comp_size'], human(h['comp_size'])))
        print('  file        %d bytes (%s)' % (h['file_size'], human(h['file_size'])))
        print('  ratio       %.4f%%  (%.1fx)' % (ratio, 100.0 / ratio if ratio else 0))
        print('  crc32       %08x   head preview %d bytes   block %s'
              % (h['crc'], h['head_len'], human(h['block_size'])))


def cmd_verify(args):
    bad = 0
    for path in args.path:
        try:
            if args.against:
                with open(args.against, 'rb') as orig:
                    state = {'ok': True, 'pos': 0}

                    def sink(buf):
                        if not state['ok']:
                            return
                        if orig.read(len(buf)) != buf:
                            state['ok'] = False
                        state['pos'] += len(buf)

                    h = stream_inflate(path, sink)
                if not state['ok'] or state['pos'] != h['raw_size']:
                    raise PackError('%s: byte comparison with %s failed'
                                    % (path, args.against))
                print('OK    %s  [%s] size %d, crc %08x, byte-identical'
                      % (path, h['codec_name'], h['measured_raw'], h['measured_crc']))
            else:
                h = stream_inflate(path, lambda buf: None)
                print('OK    %s  [%s] size %d, crc %08x'
                      % (path, h['codec_name'], h['measured_raw'], h['measured_crc']))
        except (PackError, OSError) as e:
            bad += 1
            print('FAIL  %s: %s' % (path, e), file=sys.stderr)
    if bad:
        raise PackError('%d file(s) failed verification' % bad)


def cmd_unpack(args):
    for path in args.path:
        h = read_header(path)
        dst = args.output if (args.output and len(args.path) == 1) else os.path.splitext(path)[0] + '.json'
        if os.path.exists(dst) and not args.force:
            raise PackError('%s: output exists (use --force)' % dst)
        os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
        tmp = dst + '.tmp'
        try:
            with open(tmp, 'wb') as fo:
                stream_inflate(path, fo.write)
            os.replace(tmp, dst)
        except BaseException:
            try:
                os.remove(tmp)
            except OSError:
                pass
            raise
        print('unpack %s -> %s  (%s, %s)' % (path, dst, h['codec_name'],
                                             human(h['raw_size'])))


def _build_haxe(workdir):
    """Compile engine-side ChartCodec + PackedScanner + lime LZMA into a CLI."""
    cp = os.path.join(workdir, 'cp')
    os.makedirs(os.path.join(cp, 'backend'), exist_ok=True)
    for name in ('ChartCodec.hx', 'ChartHeader.hx', 'PackedScanner.hx', 'PackedChart.hx'):
        src = os.path.join(REPO_ROOT, 'source', 'backend', name)
        if not os.path.isfile(src):
            raise PackError('missing engine source: %s' % src)
        shutil.copy(src, os.path.join(cp, 'backend', name))
    shutil.copy(SELFTEST_SRC, os.path.join(cp, 'ChartCodecSelfTest.hx'))
    env = dict(os.environ)
    # Intel Homebrew toolchain under Rosetta; host NEKOPATH may point to arm64.
    for candidate in ('/usr/local/lib/neko', '/opt/homebrew/lib/neko'):
        if os.path.isfile(os.path.join(candidate, 'std.ndll')):
            env['NEKOPATH'] = candidate
            break
    out_cpp = os.path.join(workdir, 'cpp')
    build = subprocess.run(
        ['haxe', '-lib', 'lime', '-main', 'ChartCodecSelfTest',
         '-cp', cp, '-cpp', out_cpp],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        universal_newlines=True)
    if build.returncode != 0:
        raise PackError('haxe build failed:\n%s' % build.stdout[-4000:])
    exe = os.path.join(out_cpp, 'ChartCodecSelfTest')
    if not os.path.isfile(exe):
        raise PackError('haxe produced no executable at %s' % exe)
    if os.path.isfile(NDLL_SRC):
        shutil.copy(NDLL_SRC, os.path.join(out_cpp, 'lime.ndll'))
    return exe


def cmd_scancheck(args):
    """Prove a packed chart scans into exactly the same note clusters."""
    work = tempfile.mkdtemp(prefix='chartpack_scancheck_')
    try:
        exe = _build_haxe(work)
        run = subprocess.run([exe, args.mec, '--scanner-only', args.json],
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             universal_newlines=True)
        if run.returncode != 0 or 'SCANNER_OK' not in run.stdout:
            raise PackError('scanner equivalence check failed:\n%s' % run.stdout[-4000:])
        print(run.stdout.strip())
        print('SCANCHECK PASS  %s' % args.mec)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def _haxe_cross_check(exe, mec_path, original_path, workdir, quiet):
    out_json = os.path.join(workdir, 'haxe_out.json')
    run = subprocess.run([exe, mec_path, out_json, original_path],
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         universal_newlines=True)
    if (run.returncode != 0 or 'HAXE_OK' not in run.stdout
            or 'SCANNER_OK' not in run.stdout):
        raise PackError('hxcpp decoder/scanner failed:\n%s' % run.stdout[-4000:])
    with open(original_path, 'rb') as a, open(out_json, 'rb') as b:
        if a.read() != b.read():
            raise PackError('hxcpp decoder output differs from original .json')
    with open(out_json + '.head', 'rb') as b:
        head_bytes = b.read()
    with open(original_path, 'rb') as a:
        if a.read(len(head_bytes)) != head_bytes:
            raise PackError('hxcpp head preview differs from original .json')
    if not quiet:
        for line in run.stdout.splitlines():
            if line.startswith(('HAXE_OK', 'SCANNER_OK')):
                print('  hxcpp ' + line)


def cmd_selftest(args):
    work = tempfile.mkdtemp(prefix='chartpack_selftest_')
    try:
        import json as _json
        notes = []
        for s in range(12):
            notes.append({
                'sectionNotes': [[i * 16.0 + s * 4096, i % 8, 0, 'Alt Animation']
                                 for i in range(3000)],
                'sectionBeats': 4, 'typeOfSection': 0,
                'mustHitSection': s % 2 == 0, 'gfSection': False,
                'bpm': 180, 'changeBPM': False, 'altAnim': False,
            })
        payload = {'song': {
            'song': 'chartpack-selftest', 'bpm': 180, 'speed': 3.2,
            'needsVoices': True, 'player1': 'bf', 'player2': 'dad',
            'gfVersion': 'gf', 'stage': 'stage', 'keys': 4,
            'format': 'psych_v1', 'notes': notes,
            'events': [[0, [['Change Character', 'bf', 'pico']]]],
        }}
        src = os.path.join(work, 'sample.json')
        with open(src, 'wb') as f:
            f.write(_json.dumps(payload, ensure_ascii=False,
                                separators=(',', ':')).encode('utf-8'))

        exe = None if args.no_haxe else _build_haxe(work)
        for codec in ('deflate', 'lzma', 'struct'):
            print('--- codec %s ---' % codec, flush=True)
            mec = os.path.join(work, 'sample_%s.mec' % codec)
            restored = os.path.join(work, 'restored_%s.json' % codec)
            print(pack_one(src, mec, 9, True, True, False, False,
                           0, codec), flush=True)
            h = read_header(mec)
            print('  ratio %.3f%%' % (100.0 * h['file_size'] / h['raw_size']), flush=True)
            cmd_verify(argparse.Namespace(path=[mec], against=src))
            cmd_unpack(argparse.Namespace(path=[mec], output=restored, force=True))
            with open(src, 'rb') as a, open(restored, 'rb') as b:
                assert a.read() == b.read(), 'unpack mismatch for %s' % codec
            if exe is not None:
                _haxe_cross_check(exe, mec, src, work, args.quiet)
                print('  hxcpp decoder: bytes + head preview + clusters identical')
        print('SELFTEST PASS (3 codecs)')
    finally:
        if args.keep:
            print('workdir kept: %s' % work)
        else:
            shutil.rmtree(work, ignore_errors=True)


def build_parser():
    p = argparse.ArgumentParser(
        prog='chartpack.py',
        description='Meteoric Engine chart packer: byte-lossless .json <-> .mec',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__.split('Commands:')[-1])
    sub = p.add_subparsers(dest='command', required=True)

    pk = sub.add_parser('pack', help='compress chart .json into .mec')
    pk.add_argument('path', help='a .json file, or a directory to scan recursively')
    pk.add_argument('--codec', default=DEFAULT_CODEC, choices=list(CODEC_IDS),
                    help='struct (default, smallest), lzma, or deflate (v1 compat)')
    pk.add_argument('--level', type=int, default=9, choices=range(1, 10),
                    metavar='1-9', help='zlib level for --codec deflate (default 9)')
    pk.add_argument('--block-size', type=int, default=BLOCK_SIZE, metavar='BYTES',
                    help='LZMA block size for --codec lzma (default 16MiB)')
    pk.add_argument('--output', help='output directory (mirror relative layout)')
    pk.add_argument('--force', action='store_true', help='overwrite existing .mec')
    pk.add_argument('--dry-run', action='store_true', help='list files only')
    pk.add_argument('--min-size', type=int, default=4096, metavar='BYTES',
                    help='skip .json smaller than this (default 4096; 0 = pack everything)')
    pk.add_argument('--quiet', action='store_true', help='no per-chunk progress')
    pk.add_argument('--keep-going', action='store_true', help='continue on per-file errors')
    pk.add_argument('--delete-source', action='store_true',
                    help='delete source .json AFTER a verified byte-identical round trip')
    pk.add_argument('--yes', action='store_true',
                    help='required together with --delete-source')
    pk.set_defaults(func=cmd_pack)

    up = sub.add_parser('unpack', help='restore original .json bytes')
    up.add_argument('path', nargs='+', help='.mec file(s)')
    up.add_argument('--output', help='output .json path (single input only)')
    up.add_argument('--force', action='store_true', help='overwrite existing file')
    up.set_defaults(func=cmd_unpack)

    inf = sub.add_parser('info', help='print container header')
    inf.add_argument('path', nargs='+', help='.mec file(s)')
    inf.set_defaults(func=cmd_info)

    vf = sub.add_parser('verify', help='check CRC32/size and optional byte equality')
    vf.add_argument('path', nargs='+', help='.mec file(s)')
    vf.add_argument('--against', help='also compare decompressed bytes with this .json')
    vf.set_defaults(func=cmd_verify)

    st = sub.add_parser('selftest', help='all codecs: round trip + hxcpp decoder check')
    st.add_argument('--no-haxe', action='store_true', help='skip hxcpp cross-check')
    st.add_argument('--quiet', action='store_true', help='less haxe output')
    st.add_argument('--keep', action='store_true', help='keep temp workdir')
    st.set_defaults(func=cmd_selftest)

    sc = sub.add_parser('scancheck',
                        help='verify a .mec scans into the same note clusters as its .json')
    sc.add_argument('mec', help='packed .mec file')
    sc.add_argument('json', help='original .json chart')
    sc.set_defaults(func=cmd_scancheck)
    return p


def main():
    args = build_parser().parse_args()
    try:
        args.func(args)
    except (PackError, OSError, AssertionError) as e:
        print('ERROR: %s' % e, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
