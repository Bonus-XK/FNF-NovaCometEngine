package backend;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.zip.Uncompress;
import haxe.zip.FlushMode;

/**
 * `.mec` = Meteoric Engine Chart —— 模组谱面二进制压缩容器。
 *
 * 设计目标：给「大型粪谱」（GB 级 JSON）做离线高倍压缩，且不破坏引擎原有的
 * JSON 语义与零 DOM 快速解析路径。三种 codec 全部**字节级无损**。
 *
 * ===== 容器布局（全部 little-endian，固定 64 字节头）=====
 *   0   4   magic  'MEC1'
 *   4   1   version 1 = deflate 单流；2 = 分块容器（codec 见下）
 *   5   1   flags   bit0 = CRC32 有效；bit1..2 = codec
 *                   (0=deflate, 1=分块 LZMA, 2=结构化)
 *   6   2   headLen 原 JSON 头部预览字节数（<= 8192）
 *   8   8   rawSize 原始 JSON 字节数（u64）
 *   16  8   compSize 压缩载荷字节数（u64）
 *   24  4   crc32   原始 JSON 的 CRC32
 *   28  4   blockSize 分块原始大小（v1 = 0）
 *   32  32  reserved = 0
 *   64  headLen   原 JSON 前 headLen 字节（**未压缩**）
 *                 供 Song.readHead() 免解压读元数据。
 *   64+headLen ... compSize 字节：按 codec 解释的压缩载荷。
 *
 * ===== codec 载荷 =====
 * deflate : 单个 zlib DEFLATE 流（RFC1950，wbits=15，zlib wrapper）。
 * LZMA    : 连续 [u32 frameLen][lime LZMA1 帧]，每块独立字典，流式解码。
 * struct  : 7 个固定顺序的 [u32 frameLen][lime LZMA1 帧]：
 *           skeleton / times / rests / colDict / tdelta / cols / restidx。
 *           详见 inflateStructured()。
 *
 * 解码后的字节与源 .json **完全一致**（不紧凑化、不重排字段、不重写数字文本），
 * 因此 unpack 可逐字节还原，也不改变 fastParseSong / PackedScanner
 * 等按字节扫描的解析行为。
 *
 * ===== 端序 =====
 * 头里的多字节整数一律手工按字节读写（显式 LE），不依赖
 * haxe.io.Bytes.getInt32/setInt32 的平台端序，保证 Python 工具与
 * hxcpp 引擎跨平台一致。
 *
 * ===== 依赖与内存 =====
 * 本类不做文件 IO（由 Song 负责），也不直接依赖 lime：
 * LZMA1 解码器由 Song.ensureCodec() 注入 lzmaDecoder。
 * `inflate()` 以 OUT_CHUNK 为粒度回调，调用方可边解压边喂 PackedScanner；
 * deflate / LZMA 路径不整份物化解压产物，struct 路径需要 ~1/3 原始大小的
 * 字典与索引流常驻（换取最高压缩率）。`inflateToString()` 只用于小谱面。
 */
class ChartCodec
{
	public static inline var EXT:String = 'mec';
	public static inline var MAGIC:String = 'MEC1';
	public static inline var VERSION_V1:Int = 1; // deflate 单流
	public static inline var VERSION_V2:Int = 2; // 分块容器（codec 由 flags 决定）
	public static inline var HEADER_SIZE:Int = 64;
	public static inline var HEAD_PREVIEW_MAX:Int = 8192;
	public static inline var OUT_CHUNK:Int = 256 * 1024;
	public static inline var FLAG_CRC32:Int = 1;
	/** codec = (flags >> 1) & 3 */
	public static inline var CODEC_DEFLATE:Int = 0;
	public static inline var CODEC_LZMA:Int = 1;
	public static inline var CODEC_STRUCT:Int = 2;

	/** v3 固定 7 条流：skeleton, times, rests, colDict, tdelta, cols, restidx */
	static inline var STRUCT_STREAMS:Int = 7;
	/** skeleton 中用 0x00 标记一个被抽出的音符元组（JSON 不允许裸 NUL 字节） */
	static inline var STRUCT_MARK:Int = 0;

	/**
	 * LZMA1 解码器由引擎侧注入（lime.utils.Bytes.decompress(LZMA)）。
	 * ChartCodec 本身保持纯 Haxe / 零外部依赖，便于离线工具独立编译自测。
	 * 入参 = 单个 lime 格式 LZMA 帧（5B props + 8B LE 原始长度 + raw LZMA1 数据）。
	 */
	public static var lzmaDecoder:Bytes->Bytes = null;

	/** 不读盘，纯路径后缀判断。 */
	public static function isPackedPath(path:String):Bool
	{
		if (path == null) return false;
		var dot:Int = path.lastIndexOf('.');
		return dot >= 0 && path.substr(dot + 1).toLowerCase() == EXT;
	}

	static inline function u16(b:Bytes, p:Int):Int
	{
		return (b.get(p) & 255) | ((b.get(p + 1) & 255) << 8);
	}

	/** u32 以 Float 返回，避免 0x80000000 以上翻负。 */
	static inline function u32(b:Bytes, p:Int):Float
	{
		return (b.get(p) & 255)
			+ (b.get(p + 1) & 255) * 256.0
			+ (b.get(p + 2) & 255) * 65536.0
			+ (b.get(p + 3) & 255) * 16777216.0;
	}

	static inline function u64(b:Bytes, p:Int):Float
	{
		return u32(b, p) + u32(b, p + 4) * 4294967296.0;
	}

	public static function isPacked(bytes:Bytes):Bool
	{
		if (bytes == null || bytes.length < HEADER_SIZE) return false;
		return bytes.get(0) == 77  // M
			&& bytes.get(1) == 69  // E
			&& bytes.get(2) == 67  // C
			&& bytes.get(3) == 49; // 1
	}

	/** 只解析头；不要求传入完整文件（可只给前 HEADER_SIZE 字节）。 */
	public static function readHeader(bytes:Bytes):ChartHeader
	{
		if (!isPacked(bytes)) throw 'ChartCodec: bad magic (not a .mec file)';
		var version:Int = bytes.get(4);
		if (version != VERSION_V1 && version != VERSION_V2)
			throw 'ChartCodec: unsupported version ' + version;
		var headLen:Int = u16(bytes, 6);
		if (headLen > HEAD_PREVIEW_MAX) throw 'ChartCodec: head preview too large ' + headLen;
		var flags:Int = bytes.get(5);
		var h:ChartHeader =
		{
			version: version,
			flags: flags,
			headLen: headLen,
			rawSize: u64(bytes, 8),
			compSize: u64(bytes, 16),
			crc32: u32(bytes, 24),
			dataOffset: HEADER_SIZE + headLen,
			codec: version == VERSION_V1 ? CODEC_DEFLATE : ((flags >> 1) & 3),
			blockSize: version == VERSION_V1 ? 0 : Std.int(u32(bytes, 28))
		};
		if (h.rawSize < 1) throw 'ChartCodec: empty payload';
		if (h.compSize < 1) throw 'ChartCodec: empty compressed stream';
		if (h.compSize > 2147483000) throw 'ChartCodec: payload exceeds 2GB';
		if (h.version == VERSION_V2 && h.blockSize < 1)
			throw 'ChartCodec: v2 requires a positive block size';
		return h;
	}

	/** 头部预览文本（原 JSON 前 headLen 字节）；常用于 Song.readHead()。 */
	public static function headText(bytes:Bytes, h:ChartHeader, ?maxLen:Int = 8192):String
	{
		var want:Int = h.headLen;
		if (maxLen != null && want > maxLen) want = maxLen;
		if (want <= 0 || bytes.length < HEADER_SIZE + want) return '';
		return bytes.sub(HEADER_SIZE, want).toString();
	}

	/**
	 * 流式解压整个容器。`onChunk(buf, len)` 中的 buf 是复用缓冲区，
	 * 只有前 len 字节有效，回调必须立即消费（不得保存引用）。
	 * 返回解压后的总字节数；与 rawSize 不符会抛错。
	 */
	public static function inflate(bytes:Bytes, onChunk:Bytes->Int->Void):Float
	{
		var h:ChartHeader = readHeader(bytes);
		if (bytes.length != h.dataOffset + h.compSize)
			throw 'ChartCodec: file size mismatch (expected ' + (h.dataOffset + h.compSize) + ', got ' + bytes.length + ')';

		var total:Float = 0;
		if (h.codec == CODEC_DEFLATE)
			total = inflateDeflate(bytes, h, onChunk);
		else if (h.codec == CODEC_LZMA)
			total = inflateLzmaBlocks(bytes, h, onChunk);
		else if (h.codec == CODEC_STRUCT)
			total = inflateStructured(bytes, h, onChunk);
		else
			throw 'ChartCodec: unsupported codec ' + h.codec;

		if (total != h.rawSize)
			throw 'ChartCodec: decompressed size mismatch (expected ' + h.rawSize + ', got ' + total + ')';
		return total;
	}

	/** v1：单个 zlib DEFLATE 流（wbits=15）。 */
	static function inflateDeflate(bytes:Bytes, h:ChartHeader, onChunk:Bytes->Int->Void):Float
	{
		var u:Uncompress = new Uncompress(null); // null => MAX_WBITS(15) => zlib wrapper
		u.setFlushMode(FlushMode.SYNC);
		var out:Bytes = Bytes.alloc(OUT_CHUNK);
		var pos:Int = h.dataOffset;
		var total:Float = 0;
		var stall:Int = 0;
		while (true)
		{
			var r = u.execute(bytes, pos, out, 0);
			if (r.write > 0)
			{
				onChunk(out, r.write);
				total += r.write;
			}
			pos += r.read;
			if (r.done) break;
			if (r.read == 0 && r.write == 0)
			{
				if (++stall > 4) { u.close(); throw 'ChartCodec: truncated deflate stream'; }
			}
			else stall = 0;
		}
		u.close();
		return total;
	}

	/**
	 * v2：载荷 = 连续 `[u32 frameLen][lime LZMA1 帧]`。
	 * 每块独立字典（默认 16MB 原始数据），逐块解码、按 OUT_CHUNK 分块回调，
	 * 因此解压不会整份物化，峰值内存与谱面总大小无关。
	 */
	static function inflateLzmaBlocks(bytes:Bytes, h:ChartHeader, onChunk:Bytes->Int->Void):Float
	{
		if (lzmaDecoder == null) throw 'ChartCodec: LZMA decoder not registered';
		var pos:Int = h.dataOffset;
		var end:Int = h.dataOffset + Std.int(h.compSize);
		var total:Float = 0;
		var blocks:Int = 0;
		while (pos < end)
		{
			if (pos + 4 > end) throw 'ChartCodec: truncated LZMA frame table';
			var frameLen:Int = Std.int(u32(bytes, pos));
			pos += 4;
			if (frameLen < 13 || pos + frameLen > end)
				throw 'ChartCodec: bad LZMA frame length ' + frameLen;
			var frame:Bytes = bytes.sub(pos, frameLen);
			pos += frameLen;
			var declared:Float = u64(frame, 5);
			var raw:Bytes = lzmaDecoder(frame);
			if (raw == null) throw 'ChartCodec: LZMA decode failed in block ' + blocks;
			if (raw.length != declared)
				throw 'ChartCodec: LZMA block size mismatch (expected ' + declared + ', got ' + raw.length + ')';
			var p:Int = 0;
			while (p < raw.length)
			{
				var len:Int = raw.length - p;
				if (len > OUT_CHUNK) len = OUT_CHUNK;
				onChunk(raw.sub(p, len), len);
				p += len;
				total += len;
			}
			blocks++;
		}
		return total;
	}

	// ========================================================================
	// v3 结构化 codec —— 字节级无损重建
	//
	// 工具把每个音符元组 `[t,col,rest]` 从原 JSON 里抽走，skeleton 在对应
	// 位置留一个 0x00 标记；数值分别列式存放（时间索引 delta / 列号字典索引 /
	// rest 字典索引，均 varint），字典保存原始字节文本。解码时按字典把元组
	// 文本原样拼回，因此输出与源 .json **逐字节一致**，不是"语义等价"。
	//
	// 载荷 = 7 个顺序固定的 `[u32 frameLen][lime LZMA1 帧]`：
	//   0 skeleton | 1 times | 2 rests | 3 colDict | 4 tdelta | 5 cols | 6 restidx
	// 字典流是 `条目 + '\n'` 拼接；索引流是 LEB128 varint。
	// ========================================================================

	static function readFrame(bytes:Bytes, pos:Int, consumed:Array<Int>, end:Int):Bytes
	{
		if (pos + 4 > end) throw 'ChartCodec: truncated structured frame table';
		var len:Int = Std.int(u32(bytes, pos));
		if (len < 13 || pos + 4 + len > end) throw 'ChartCodec: bad structured frame length ' + len;
		consumed[0] = 4 + len;
		var raw:Bytes = lzmaDecoder(bytes.sub(pos + 4, len));
		if (raw == null) throw 'ChartCodec: LZMA decode failed (structured stream)';
		return raw;
	}

	static function readVarint(b:Bytes, p:Int, consumed:Array<Int>):Int
	{
		var v:Int = 0;
		var shift:Int = 0;
		var n:Int = 0;
		while (true)
		{
			var c:Int = b.get(p + n);
			n++;
			v |= (c & 127) << shift;
			if ((c & 128) == 0) break;
			shift += 7;
		}
		consumed[0] = n;
		return v;
	}

	/** 把 `条目\n` 流拆成起始偏移 + 长度数组（不产生字符串对象）。 */
	static function splitDict(b:Bytes, starts:Array<Int>, lens:Array<Int>):Void
	{
		var s:Int = 0;
		for (i in 0...b.length)
		{
			if (b.get(i) == 10)
			{
				starts.push(s);
				lens.push(i - s);
				s = i + 1;
			}
		}
	}

	static function putBytes(src:Bytes, srcPos:Int, len:Int, dst:Bytes, dstPos:Int):Int
	{
		for (i in 0...len) dst.set(dstPos + i, src.get(srcPos + i));
		return dstPos + len;
	}

	static function inflateStructured(bytes:Bytes, h:ChartHeader, onChunk:Bytes->Int->Void):Float
	{
		if (lzmaDecoder == null) throw 'ChartCodec: LZMA decoder not registered';
		var pos:Int = h.dataOffset;
		var end:Int = h.dataOffset + Std.int(h.compSize);
		var consumed:Array<Int> = [0];
		var streams:Array<Bytes> = [];
		for (i in 0...STRUCT_STREAMS)
		{
			var raw:Bytes = readFrame(bytes, pos, consumed, end);
			pos += consumed[0];
			streams.push(raw);
		}
		if (pos != end) throw 'ChartCodec: structured payload size mismatch';

		var skeleton:Bytes = streams[0];
		var times:Bytes = streams[1];
		var rests:Bytes = streams[2];
		var colDict:Bytes = streams[3];
		var tdelta:Bytes = streams[4];
		var cols:Bytes = streams[5];
		var restidx:Bytes = streams[6];

		var tStart:Array<Int> = []; var tLen:Array<Int> = [];
		var rStart:Array<Int> = []; var rLen:Array<Int> = [];
		var cStart:Array<Int> = []; var cLen:Array<Int> = [];
		splitDict(times, tStart, tLen);
		splitDict(rests, rStart, rLen);
		splitDict(colDict, cStart, cLen);

		var out:Bytes = Bytes.alloc(OUT_CHUNK);
		var outPos:Int = 0;
		var total:Float = 0;
		var sp:Int = 0;
		var dp:Int = 0; // tdelta cursor
		var cp:Int = 0; // cols cursor
		var rp:Int = 0; // restidx cursor
		var prevT:Int = 0;
		while (sp < skeleton.length)
		{
			var ch:Int = skeleton.get(sp++);
			if (ch != STRUCT_MARK)
			{
				out.set(outPos++, ch);
			}
			else
			{
				var vt:Int = readVarint(tdelta, dp, consumed); dp += consumed[0];
				// zigzag：section 之间时间可能回退，索引 delta 会是负数
				var dt:Int = (vt & 1) == 0 ? (vt >> 1) : -((vt + 1) >> 1);
				prevT += dt;
				var ci:Int = readVarint(cols, cp, consumed); cp += consumed[0];
				var ri:Int = readVarint(restidx, rp, consumed); rp += consumed[0];
				if (prevT < 0 || prevT >= tStart.length) throw 'ChartCodec: time index out of range';
				if (ci < 0 || ci >= cStart.length) throw 'ChartCodec: lane index out of range';
				if (ri < 0 || ri >= rStart.length) throw 'ChartCodec: rest index out of range';
				// 精确预留，保证一个元组不会跨输出块边界（长 noteType 也安全）
				var need:Int = 3 + tLen[prevT] + cLen[ci] + rLen[ri];
				if (need > OUT_CHUNK) throw 'ChartCodec: note tuple too large (' + need + ')';
				if (outPos + need >= OUT_CHUNK)
				{
					onChunk(out, outPos);
					total += outPos;
					outPos = 0;
				}
				out.set(outPos++, 91); // '['
				outPos = putBytes(times, tStart[prevT], tLen[prevT], out, outPos);
				out.set(outPos++, 44); // ','
				outPos = putBytes(colDict, cStart[ci], cLen[ci], out, outPos);
				outPos = putBytes(rests, rStart[ri], rLen[ri], out, outPos);
				out.set(outPos++, 93); // ']'
			}
			if (outPos >= OUT_CHUNK)
			{
				onChunk(out, outPos);
				total += outPos;
				outPos = 0;
			}
		}
		if (outPos > 0)
		{
			onChunk(out, outPos);
			total += outPos;
		}
		return total;
	}

	/** 整块解压成字符串 —— 仅供小谱面（< STREAM_CHART_MIN）使用。 */
	public static function inflateToString(bytes:Bytes):String
	{
		var bb:BytesBuffer = new BytesBuffer();
		inflate(bytes, function(b:Bytes, len:Int):Void bb.addBytes(b, 0, len));
		return bb.getBytes().toString();
	}
}
