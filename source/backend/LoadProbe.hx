package backend;

/**
 * 进曲加载时间线探针（env-gated，默认完全惰性）。
 *
 * 目的：把「选歌确认 → 加载界面 → PlayState.create → 首帧」整条链路的**每段耗时**
 * 量化成一条带 delta 的时间线，用来定位加载大头，而不是靠绝对时间戳在日志里手算。
 *
 * ⚠ 设计红线（2026-11-16 重写）：**打点过程本身绝不分配、绝不打印**。
 *   旧版每条 mark 都会 ① 拼一整行字符串（含内存采样）② Sys.println 落盘；
 *   这两步会诱发 hxcpp major GC（实测 ~90ms），而这段耗时正好记到**下一条**的 delta 上，
 *   把逐语句计时污染成假热点（曾把 Paths.image() 误判成 100ms 内存拷贝）。
 *   现在 mark 只做三件事：读一个墙钟、写两个静态数组槽、自增指针；
 *   行文本与内存数字全部推迟到 flush() 一次成形。
 *
 * 装机方式（玩家侧零影响）：
 *   METEORIC_LOADPROBE=1 ./Meteoric
 *   METEORIC_LOADPROBE_FLUSH=1   # 每 64 条落一次盘（加载中崩溃时用，会轻微污染）
 * 输出：结束时 stdout 一份 + 落盘 `crash/load_probe.txt`
 *
 * 用法约定：
 *   - mark('字面量')            —— label 必须是**编译期字面量**（hxcpp 里是静态常量，不分配）
 *   - markI('label', int)       —— 要带一个数字时用它，别在调用处拼字符串
 *   - markIR('label', int, str) —— 还要带一个已有字符串引用（文件名/角色名）时用它
 * 在调用处用 `+` 拼字符串 = 每次打点都分配，正是本类要避免的污染。
 */
class LoadProbe
{
	// 单条时间线最多记录多少点（正常进曲 60~80 条，320 是 4 倍余量）
	static inline var CAP:Int = 320;
	// 数值槽的空值标记
	static inline var NOVAL:Int = -999999;

	static var _checked:Bool = false;
	static var _on:Bool = false;
	static var _flushEach:Bool = false;
	static var _active:Bool = false;
	static var _t0:Float = 0;
	static var _tag:String = '';

	// 并行数组（首次 begin 时一次性预分配，之后只做下标赋值，不增长、不分配）
	static var _t:Array<Float> = null;
	static var _lab:Array<String> = null;
	static var _val:Array<Int> = null;
	static var _ref:Array<String> = null;
	static var _n:Int = 0;

	public static function enabled():Bool
	{
		if (_checked) return _on;
		_checked = true;
		#if sys
		try
		{
			_on = (Sys.getEnv('METEORIC_LOADPROBE') == '1');
			_flushEach = (Sys.getEnv('METEORIC_LOADPROBE_FLUSH') == '1');
		}
		catch (e:Dynamic) { _on = false; }
		#end
		return _on;
	}

	static function ensureBuffers():Void
	{
		if (_t != null) return;
		_t = [];
		_lab = [];
		_val = [];
		_ref = [];
		for (i in 0...CAP)
		{
			_t.push(0.0);
			_lab.push('');
			_val.push(NOVAL);
			_ref.push(null);
		}
	}

	/** 开始一条新的时间线（每次进曲调用一次）。tag 只在 flush 时被读，不进热路径。 */
	public static function begin(tag:String):Void
	{
		if (!enabled()) return;
		ensureBuffers();
		_n = 0;
		_tag = tag;
		_active = true;
		_t0 = haxe.Timer.stamp();
		mark('BEGIN');
	}

	/** 同 begin，但已有时间线时不重置（用于「上层已起算」的嵌套入口）。 */
	public static function beginIfInactive(tag:String):Void
	{
		if (!enabled()) return;
		if (_active) return;
		begin(tag);
	}

	/** 打一个点。label 只用字面量；未武装/已结束时立刻返回。 */
	public static function mark(label:String):Void
	{
		if (!_active) return;
		if (_n >= CAP) { _active = false; return; }
		_t[_n] = haxe.Timer.stamp();
		_lab[_n] = label;
		_val[_n] = NOVAL;
		_ref[_n] = null;
		_n++;
		if (_flushEach && (_n & 63) == 0) flush();
	}

	/** 带一个数字的点（避免在调用处拼字符串）。 */
	public static function markI(label:String, v:Int):Void
	{
		if (!_active) return;
		if (_n >= CAP) { _active = false; return; }
		_t[_n] = haxe.Timer.stamp();
		_lab[_n] = label;
		_val[_n] = v;
		_ref[_n] = null;
		_n++;
		if (_flushEach && (_n & 63) == 0) flush();
	}

	/** 带数字 + 已有字符串引用（文件名 / 角色名 / 界面类名，调用方传引用，不新建字符串）。 */
	public static function markIR(label:String, v:Int, ref:String):Void
	{
		if (!_active) return;
		if (_n >= CAP) { _active = false; return; }
		_t[_n] = haxe.Timer.stamp();
		_lab[_n] = label;
		_val[_n] = v;
		_ref[_n] = ref;
		_n++;
		if (_flushEach && (_n & 63) == 0) flush();
	}

	/** 结束时间线：打 END 点、落盘、并把整条时间线打到 stdout。未武装时无操作。 */
	public static function end():Void
	{
		if (!_active) return;
		mark('END');
		_active = false;
		flush();
	}

	public static function active():Bool return _active;

	/** 主动落盘（时间线仍在进行时也安全）。 */
	public static function flushNow():Void
	{
		if (!enabled()) return;
		flush();
	}

	static inline function fmt(ms:Float):String
	{
		return Std.string(Math.round(ms * 10) / 10);
	}

	/** 只保留文件名/末段，避免整条绝对路径把行撑爆 */
	static function shortRef(s:String):String
	{
		if (s == null) return '';
		var i:Int = s.lastIndexOf('/');
		if (i < 0) return s;
		return s.substr(i + 1);
	}

	static function memMB():Int
	{
		#if cpp
		try
		{
			var mb:Float = cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_CURRENT);
			if (Math.isFinite(mb) && mb > 0) return Std.int(mb / 1048576);
		}
		catch (e:Dynamic) {}
		#end
		return -1;
	}

	/** 把整条时间线成形成字符串（唯一会分配/打印的地方，且在计时结束之后）。 */
	static function build():String
	{
		var sb:StringBuf = new StringBuf();
		sb.add('# ' + _tag + '  mem=' + memMB() + 'mb  rss=' + Std.int(PerfProbe.processRSS()) + 'mb\n');
		var prev:Float = _t0;
		for (i in 0..._n)
		{
			var total:Float = (_t[i] - _t0) * 1000;
			var delta:Float = (_t[i] - prev) * 1000;
			prev = _t[i];
			sb.add('[');
			sb.add(fmt(total));
			sb.add(' +');
			sb.add(fmt(delta));
			sb.add('] ');
			sb.add(_lab[i]);
			if (_val[i] != NOVAL)
			{
				sb.add(' = ');
				sb.add(_val[i]);
			}
			if (_ref[i] != null)
			{
				sb.add('  @');
				sb.add(shortRef(_ref[i]));
			}
			sb.add('\n');
		}
		return sb.toString();
	}

	static function flush():Void
	{
		if (_n == 0) return;
		var txt:String = build();
		try
		{
			#if sys
			Sys.println('[LOADPROBE]\n' + txt);
			#end
		}
		catch (e:Dynamic) {}
		try
		{
			#if sys
			var dir:String = './crash';
			var envDir:String = Sys.getEnv('METEORIC_CRASH_DIR');
			if (envDir != null && envDir.length > 0) dir = envDir;
			if (!sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
			sys.io.File.saveContent(dir + '/load_probe.txt', txt);
			#end
		}
		catch (e:Dynamic)
		{
			Sys.println('[LOADPROBE] flush failed: ' + Std.string(e));
		}
	}
}
