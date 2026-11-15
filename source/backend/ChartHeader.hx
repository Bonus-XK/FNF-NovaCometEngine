package backend;

/** `.mec` 容器头（见 backend.ChartCodec 的布局说明）。 */
typedef ChartHeader =
{
	var version:Int;
	var flags:Int;
	var headLen:Int;
	var rawSize:Float;   // Float：避开 hxcpp Int32 上限（单文件可 > 2GB）
	var compSize:Float;
	var crc32:Float;
	var dataOffset:Int;
	/** 0 = deflate 单流（v1）；1 = 分块 LZMA（v2）；2 = 结构化（预留） */
	var codec:Int;
	/** v2+ 的分块原始大小（字节），v1 为 0 */
	var blockSize:Int;
}
