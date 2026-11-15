import backend.ChartCodec;
import backend.ChartHeader;
import backend.PackedScanner;
import backend.PackedChart;
import haxe.io.Bytes;
import sys.io.File;

/**
 * chartpack.py selftest 的 hxcpp 侧交叉验证。
 * 只依赖 haxe std + backend.{ChartCodec,PackedScanner,PackedChart}，
 * 不引入 flixel/openfl/lime，可在临时 classpath 里独立编译。
 *
 * argv: <file.mec> <out.json> [original.json]
 *   ① 用 ChartCodec 流式解压 .mec，输出必须与 original.json 字节一致；
 *   ② [original.json] 给出时，再比对「直接扫 JSON」与「解压后分块喂
 *      PackedScanner」两条路径产出的音符簇是否逐字段一致。
 */
class ChartCodecSelfTest
{
	static function main()
	{
		var args:Array<String> = Sys.args();
		if (args.length < 2) throw 'usage: ChartCodecSelfTest <file.mec> <out.json> [original.json] | <file.mec> --scanner-only <original.json>';

		// v2 LZMA blocks use the same native decoder the engine injects.
		ChartCodec.lzmaDecoder = function(b:Bytes):Bytes
		{
			return lime.utils.Bytes.fromBytes(b).decompress(lime.utils.CompressionAlgorithm.LZMA);
		};

		// Scanner-only mode: no decoded file is written; compare the packed
		// chart's streamed scan against a direct scan of the source .json.
		if (args[1] == '--scanner-only')
		{
			if (args.length < 3) throw 'scanner-only needs <original.json>';
			compareScanner(args[2], args[0]);
			return;
		}

		var bytes:Bytes = File.getBytes(args[0]);
		if (!ChartCodec.isPacked(bytes)) throw 'ChartCodec.isPacked() = false';
		if (!ChartCodec.isPackedPath(args[0])) throw 'ChartCodec.isPackedPath() = false';

		var h:ChartHeader = ChartCodec.readHeader(bytes);
		File.saveContent(args[1] + '.meta',
			'version=' + h.version + ' rawSize=' + h.rawSize
			+ ' compSize=' + h.compSize + ' crc32=' + h.crc32
			+ ' headLen=' + h.headLen + ' flags=' + h.flags);
		File.saveContent(args[1] + '.head', ChartCodec.headText(bytes, h, 8192));

		var out = File.write(args[1], true);
		var total:Float = ChartCodec.inflate(bytes, function(b:Bytes, len:Int):Void
		{
			out.writeBytes(b, 0, len);
		});
		out.close();

		if (total != h.rawSize) throw 'size mismatch: ' + total + ' != ' + h.rawSize;
		Sys.println('HAXE_OK total=' + total + ' rawSize=' + h.rawSize
			+ ' headPreview=' + h.headLen);

		if (args.length >= 3) compareScanner(args[2], args[0]);
	}

	/** 流式解压 + feed 必须与直接文件扫描得到完全相同的簇。 */
	static function compareScanner(jsonPath:String, mecPath:String):Void
	{
		var a:PackedScanner = new PackedScanner(0.0, true, 0);
		a.keys = 4;
		a.absoluteCols = true;
		var ca:Array<PackedChart> = a.scan(jsonPath, 180, true);
		var sa:Dynamic = a.stats();

		var b:PackedScanner = new PackedScanner(0.0, true, 0);
		b.keys = 4;
		b.absoluteCols = true;
		var packed:Bytes = File.getBytes(mecPath);
		b.beginPart(true);
		ChartCodec.inflate(packed, function(chunk:Bytes, len:Int):Void b.feed(chunk, len));
		b.endPart();
		var cb:Array<PackedChart> = b.result();
		var sb:Dynamic = b.stats();

		if (sa.raw != sb.raw || sa.merged != sb.merged || sa.clusters != sb.clusters
			|| sa.sections != sb.sections || sa.totalNotes != sb.totalNotes)
			throw 'scanner stats mismatch: json=' + Std.string(sa) + ' mec=' + Std.string(sb);
		if (ca.length != cb.length) throw 'scanner cluster count mismatch';
		for (i in 0...ca.length)
		{
			var x:PackedChart = ca[i];
			var y:PackedChart = cb[i];
			if (x.t != y.t || x.lane != y.lane || x.mustHit != y.mustHit
				|| x.density != y.density || x.holdLength != y.holdLength
				|| x.noteType != y.noteType || x.gfNote != y.gfNote
				|| x.offsKeep != y.offsKeep || x.lastOffset != y.lastOffset)
				throw 'scanner cluster mismatch at index ' + i;
		}
		Sys.println('SCANNER_OK clusters=' + ca.length + ' raw=' + sa.raw
			+ ' sections=' + sa.sections);
	}
}
