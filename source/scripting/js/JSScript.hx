package scripting.js;

#if JS_ALLOWED
import backend.QjsNative;
import cpp.RawPointer;
import haxe.Json;
import sys.io.File;

/**
 * QuickJS-backed .js script instance.
 *
 * Scope of the first slice: real ECMAScript execution (QuickJS 2024-01-13),
 * lifecycle callbacks through the same callOnScripts pipeline as Lua/HScript,
 * primitive global variables, and a JSON bridge for engine callbacks.
 * Complex Haxe objects are NOT bridged; pass primitives / arrays / objects only.
 */
class JSScript
{
	public var scriptName:String;
	public var closed:Bool = false;

	static var bridgeInstalled:Bool = false;
	static var stack:Array<JSScript> = [];

	var handle:RawPointer<Void>;
	var ready:Bool = false;
	var variables:Map<String, Dynamic> = new Map<String, Dynamic>();
	var callbacks:Map<String, Dynamic> = new Map<String, Dynamic>();

	public function new(path:String, ?code:String)
	{
		scriptName = path;
		installBridge();
		handle = QjsNative.create();
		ready = true;

		QjsNative.eval(handle, PRELUDE, '<js-prelude>');
		registerCallback('log', function(args:Dynamic) {
			trace('[JS] ' + Std.string(args));
			return null;
		});
		registerCallback('setVar', function(name:String, value:Dynamic) {
			variables.set(name, value);
			var ps = states.PlayState.instance;
			if (ps != null) ps.variables.set(name, value);
			return null;
		});
		registerCallback('getVar', function(name:String) {
			return variables.get(name);
		});

		var source:String = (code != null) ? code : File.getContent(path);
		var result:Int = QjsNative.eval(handle, source, path);
		if (result != 0)
			trace('[JS] load failed: ' + path + ' - ' + QjsNative.lastError(handle));

		call('onCreate');
	}

	static function installBridge():Void
	{
		if (bridgeInstalled) return;
		QjsNative.setBridge(cpp.Callable.fromStaticFunction(JSScript.bridge));
		bridgeInstalled = true;
	}

	/** JS -> Haxe. Returns a JSON string (always non-null). */
	public static function bridge(name:String, json:String):String
	{
		var target:JSScript = (stack.length > 0) ? stack[stack.length - 1] : null;
		if (target == null || target.closed) return 'null';

		var args:Array<Dynamic> = [];
		try
		{
			var parsed:Dynamic = Json.parse(json);
			if (Std.isOfType(parsed, Array)) args = parsed;
		}
		catch (e:Dynamic) {}

		var fn:Dynamic = target.callbacks.get(name);
		if (fn == null) return 'null';

		var result:Dynamic = null;
		try
		{
			result = Reflect.callMethod(null, fn, args);
		}
		catch (e:Dynamic)
		{
			return 'null';
		}

		try
		{
			return Json.stringify(result);
		}
		catch (e:Dynamic)
		{
			return 'null';
		}
	}

	/** Expose a Haxe function to JS under `name`. */
	public function registerCallback(name:String, fn:Dynamic):Void
	{
		callbacks.set(name, fn);
		if (ready)
		{
			var lit:String = Json.stringify(name);
			QjsNative.eval(handle,
				'globalThis[' + lit + '] = function(){ var a=Array.prototype.slice.call(arguments); a.unshift(' + lit + '); return __hxCall.apply(null,a); };',
				'<js-bridge>');
		}
	}

	public function set(name:String, value:Dynamic):Void
	{
		if (!ready) return;
		variables.set(name, value);
		if (value == null) return;
		if (Std.isOfType(value, Bool)) QjsNative.setBool(handle, name, value == true ? 1 : 0);
		else if (Std.isOfType(value, String)) QjsNative.setString(handle, name, value);
		else if (Std.isOfType(value, Int) || Std.isOfType(value, Float)) QjsNative.setNumber(handle, name, value);
	}

	public function get(name:String):Dynamic
	{
		return variables.get(name);
	}

	public function exists(name:String):Bool
	{
		return variables.exists(name) || (ready && QjsNative.hasFunction(handle, name) == 1);
	}

	public function call(func:String, args:Array<Dynamic> = null):Dynamic
	{
		if (!ready || closed || QjsNative.hasFunction(handle, func) == 0) return null;

		var jsonArgs:String = '[]';
		try
		{
			jsonArgs = Json.stringify(args == null ? [] : args);
		}
		catch (e:Dynamic)
		{
			jsonArgs = '[]';
		}

		stack.push(this);
		var out:String = '';
		try
		{
			out = QjsNative.callJson(handle, func, jsonArgs);
		}
		catch (e:Dynamic)
		{
			out = '';
		}
		stack.pop();

		if (out == '' || out == 'undefined' || out == 'null') return null;
		try
		{
			return Json.parse(out);
		}
		catch (e:Dynamic)
		{
			return out;
		}
	}

	public function destroy():Void
	{
		if (closed) return;
		call('onDestroy');
		if (ready) QjsNative.destroy(handle);
		ready = false;
		closed = true;
		variables.clear();
		callbacks.clear();
	}

	static var PRELUDE:String = '
var __hxCall = function(n) {
	var a = Array.prototype.slice.call(arguments, 1);
	var r = __hx(n, JSON.stringify(a));
	if (r === "" || r === null) return undefined;
	try { return JSON.parse(r); } catch (e) { return r; }
};
if (typeof console === "undefined") { var console = {}; }
console.log = function(){ return __hxCall("log", Array.prototype.slice.call(arguments)); };
';
}
#end
