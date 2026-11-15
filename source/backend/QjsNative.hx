package backend;

#if JS_ALLOWED
import cpp.RawPointer;
import cpp.Callable;

/**
 * Thin @:native binding over third_party/quickjs/qjs_glue.cpp.
 * The QuickJS C sources are pulled into the main hxcpp target by QjsBuild/qjs.xml
 * (same static-binding approach as linc_luajit); there is no ndll and no CFFI load.
 */
@:keep
@:include('qjs_glue.h')
/* Inline @:buildXml (no macro): this project has a global source/import.hx that pulls
 * llua.* (cpp.RawPointer) into macro context, so any Haxe macro fails to compile here
 * (see compile-mac.sh:219-222). Paths are relative to the generated hxcpp obj dir,
 * same convention as Main.hx:34 (../../../../art/icon.rc). */
@:buildXml('<set name="QJS_PATH" value="../../../../third_party/quickjs/"/>
<include name="../../../../third_party/quickjs/qjs.xml" />')
extern class QjsNative
{
	@:native('qjs_create') static function create():RawPointer<Void>;
	@:native('qjs_destroy') static function destroy(handle:RawPointer<Void>):Void;

	@:native('qjs_eval') static function eval(handle:RawPointer<Void>, code:String, filename:String):Int;
	@:native('qjs_last_error') static function lastError(handle:RawPointer<Void>):String;

	@:native('qjs_set_number') static function setNumber(handle:RawPointer<Void>, name:String, value:Float):Void;
	@:native('qjs_set_string') static function setString(handle:RawPointer<Void>, name:String, value:String):Void;
	@:native('qjs_set_bool') static function setBool(handle:RawPointer<Void>, name:String, value:Int):Void;

	@:native('qjs_get_number') static function getNumber(handle:RawPointer<Void>, name:String):Float;
	@:native('qjs_get_string') static function getString(handle:RawPointer<Void>, name:String):String;
	@:native('qjs_has_function') static function hasFunction(handle:RawPointer<Void>, name:String):Int;

	@:native('qjs_call_json') static function callJson(handle:RawPointer<Void>, name:String, jsonArgs:String):String;
	@:native('qjs_set_bridge') static function setBridge(fn:Callable<String->String->String>):Void;
}
#end
