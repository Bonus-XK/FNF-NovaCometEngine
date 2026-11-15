package backend;

/**
 * 演出编排缓动工具（Different Creatingness Engine 兼容）。
 *
 * custom: 缓动 token = 16 个 0..1 采样点的逗号串（`custom:0,0.05,...`），运行时线性插值求值；
 * 另提供 INSTANT / CLASSIC 两个「瞬时」token 判定（DCE 同名约定：出现即忽略时长、直接落位）。
 * 编码/解码与 DCE 的 CustomEase.hx 完全同构，cam.json 里写出的曲线 DCE 可直接读。
 */
class ChoreoEase
{
	public static inline var SAMPLES:Int = 16;

	public static function defaultCurve():Array<Float>
	{
		var a:Array<Float> = [];
		for (i in 0...SAMPLES)
			a.push(i / (SAMPLES - 1));
		return a;
	}

	public static function encode(samples:Array<Float>):String
	{
		var parts:Array<String> = [];
		for (s in samples)
			parts.push(Std.string(Math.round(s * 1000) / 1000));
		return parts.join(',');
	}

	public static function decode(token:String):Array<Float>
	{
		var body:String = token.indexOf(':') >= 0 ? token.substring(token.indexOf(':') + 1) : token;
		var arr:Array<String> = body.split(',');
		var out:Array<Float> = [];
		for (p in arr)
		{
			var v:Float = Std.parseFloat(p);
			if (Math.isNaN(v)) v = 0;
			out.push(Math.max(0, Math.min(1, v)));
		}
		while (out.length < SAMPLES)
			out.push(out.length > 0 ? out[out.length - 1] : 0);
		while (out.length > SAMPLES)
			out.pop();
		return out;
	}

	public static function eval(samples:Array<Float>, t:Float):Float
	{
		if (samples == null || samples.length == 0) return t;
		if (t <= 0) return samples[0];
		if (t >= 1) return samples[samples.length - 1];
		var x:Float = t * (samples.length - 1);
		var i:Int = Math.floor(x);
		if (i >= samples.length - 1) return samples[samples.length - 1];
		var f:Float = x - i;
		return samples[i] + (samples[i + 1] - samples[i]) * f;
	}

	/** token 是否带 custom: 前缀。 */
	public static function isCustomToken(token:String):Bool
	{
		return token != null && token.indexOf('custom:') == 0;
	}

	/** DCE 约定：token 任一段为 CLASSIC = 瞬时（观感与旧版引擎一致）。 */
	public static function isClassicToken(token:String):Bool
	{
		if (token == null) return false;
		for (p in token.split(','))
			if (StringTools.trim(p).toUpperCase() == 'CLASSIC') return true;
		return false;
	}

	/** DCE 约定：token 任一段为 INSTANT = 瞬时。 */
	public static function isInstantToken(token:String):Bool
	{
		if (token == null) return false;
		for (p in token.split(','))
			if (StringTools.trim(p).toUpperCase() == 'INSTANT') return true;
		return false;
	}

	/** INSTANT 或 CLASSIC —— 两者都视为「忽略时长直接落位」。 */
	public static function isSnapToken(token:String):Bool
	{
		return isInstantToken(token) || isClassicToken(token);
	}

	/**
	 * 解析缓动 token 为 flixel 缓动函数。
	 * custom: 前缀走采样曲线；INSTANT/CLASSIC 返回 null（调用方应按瞬时落位处理）；
	 * 其余交给 LuaUtils.getTweenEaseByString（未知名回退 linear）。
	 */
	public static function resolve(token:String):Null<Float->Float>
	{
		if (token == null) return null;
		var t:String = StringTools.trim(token);
		if (t.length == 0) return null;
		if (isSnapToken(t)) return null;
		if (isCustomToken(t))
		{
			var samples:Array<Float> = decode(t);
			return function(f:Float):Float { return eval(samples, f); };
		}
		return scripting.lua.LuaUtils.getTweenEaseByString(t);
	}
}
