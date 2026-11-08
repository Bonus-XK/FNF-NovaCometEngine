package objects;

import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.util.FlxColor;
import backend.HudStyles;
import openfl.display.BitmapData;
import openfl.display.Shape;
import openfl.geom.Rectangle;

class HealthBar extends FlxSpriteGroup
{
	public var leftBar:FlxSprite;
	public var rightBar:FlxSprite;
	public var bg:FlxSprite;
	public var valueFunction:Void->Float = function() return 0;
	public var percent(default, set):Float = 0;
	public var bounds:Dynamic = {min: 0, max: 1};
	public var leftToRight(default, set):Bool = true;
	public var barCenter(default, null):Float = 0;

	// 填充左右颜色（setColors 记录），用于新版血条外框跟随血量多的一方
	var leftColor:FlxColor = FlxColor.WHITE;
	var rightColor:FlxColor = FlxColor.BLACK;

	// you might need to change this if you want to use a custom bar
	public var barWidth(default, set):Int = 1;
	public var barHeight(default, set):Int = 1;
	public var barOffset:FlxPoint = new FlxPoint(3, 3);
	public var borderSize(default, set):Int = 0;
	public var hollowShape:Bool = false;

	var _image:String = 'healthBar';
	var _useNew:Bool = false;
	var _useRounded:Bool = false; // 流星圆角档：黑色圆角底 + 内缩 2px 圆角填充（TimeBar newTimeBarStyle 同款机制）
	var _roundMask:BitmapData = null; // 圆角填充遮罩（buildBg 圆角分支生成，与 bg 同尺寸）

	public function new(x:Float, y:Float, image:String = 'healthBar', valueFunction:Void->Float = null, boundX:Float = 0, boundY:Float = 1,
			?oldVersion:Bool = false)
	{
		super(x, y);

		if(valueFunction != null) this.valueFunction = valueFunction;
		setBounds(boundX, boundY);

		_image = image;
		_useNew = ClientPrefs.data.newHealthBar;
		_useRounded = (ClientPrefs.data.healthBarStyle == HudStyles.HB_ROUNDED);
		buildBg();

		leftBar = new FlxSprite().makeGraphic(Std.int(bg.width), Std.int(bg.height), FlxColor.WHITE);
		//leftBar.color = FlxColor.WHITE;
		leftBar.antialiasing = antialiasing = ClientPrefs.data.antialiasing;

		rightBar = new FlxSprite().makeGraphic(Std.int(bg.width), Std.int(bg.height), FlxColor.WHITE);
		rightBar.color = FlxColor.BLACK;
		rightBar.antialiasing = ClientPrefs.data.antialiasing;

		if (_useRounded && _roundMask != null)
		{
			// 圆角档：填充精灵换成遮罩位图（白色圆角形状），setColors 的颜色乘上去就是彩色圆角填充
			leftBar.pixels = _roundMask.clone();
			rightBar.pixels = _roundMask.clone();
			rightBar.color = FlxColor.BLACK;
		}
		else
		{
			checkForHollowShape();
		}

		add(bg);
		add(leftBar);
		add(rightBar);
		regenerateClips();
	}

	// 创建/重建血条背景：新版自绘（不依赖贴图，融合 0.6.3）／流星圆角（纯代码）／旧版加载贴图
	function buildBg():Void
	{
		var barW:Int = 601;
		var barH:Int = 19;

		if(_useRounded)
		{
			// 流星圆角：黑色圆角底 601×19（同经典几何，图标/hudLayout 数学不变）
			// + 内缩 2px 的圆角填充遮罩（clipRect 驱动，零每帧重绘）
			generateRoundedBackground();
			bg.antialiasing = ClientPrefs.data.antialiasing;
			barWidth = barW - 4;
			barHeight = barH - 4;
			barOffset.set(2, 2);
			return;
		}
		else if(_useNew)
		{
			try {
				var g = Paths.image(_image);
				if (g != null) { barW = Std.int(g.width); barH = Std.int(g.height); }
			} catch (e:Dynamic) {}
			// 白边框底（0.6.3 createFilledBar 风格），填充用 barOffset 内边距，形成边框
			bg = new FlxSprite().makeGraphic(barW, barH, FlxColor.WHITE);
		}
		else
		{
			bg = new FlxSprite().loadGraphic(Paths.image(_image));
			barW = Std.int(bg.width);
			barH = Std.int(bg.height);
		}
		bg.antialiasing = ClientPrefs.data.antialiasing;
		barWidth = barW - 6;
		barHeight = barH - 6;
	}

	// 流星圆角底 + 填充遮罩（TimeBar.generateModernBackground 同款：Shape 一次性绘制，运行时零重绘）
	function generateRoundedBackground():Void
	{
		var w:Int = 601;
		var h:Int = 19;
		var border:Int = 2;

		var maskBitmap:BitmapData = new BitmapData(w, h, true, 0x00000000);
		var maskShape:Shape = new Shape();
		maskShape.graphics.beginFill(0xFFFFFFFF, 1);
		maskShape.graphics.drawRoundRect(border, border, w - border * 2, h - border * 2, 6, 6);
		maskShape.graphics.endFill();
		maskBitmap.draw(maskShape);
		_roundMask = maskBitmap;

		var bitmap:BitmapData = new BitmapData(w, h, true, 0x00000000);
		var shape:Shape = new Shape();
		shape.graphics.beginFill(0xFF000000, 1);
		shape.graphics.drawRoundRect(0, 0, w, h, 8, 8);
		shape.graphics.endFill();
		bitmap.draw(shape);

		bg = new FlxSprite().makeGraphic(w, h, FlxColor.TRANSPARENT);
		bg.pixels = bitmap;
	}

	// 运行时切换血条样式（设置改变后立即生效）。style = backend.HudStyles.HB_* 存档值
	public function setStyle(style:String):Void
	{
		var useNew:Bool = (style == HudStyles.HB_NEW);
		var useRounded:Bool = (style == HudStyles.HB_ROUNDED);
		if (_useNew == useNew && _useRounded == useRounded) return;
		_useNew = useNew;
		_useRounded = useRounded;
		rebuildBars();
	}

	// 按当前 _useNew/_useRounded 重建背景与填充精灵（buildBg + 遮罩位图 + 几何复位）
	function rebuildBars():Void
	{
		if (bg == null) return;
		remove(bg);
		buildBg();
		insert(0, bg);
		leftBar.setGraphicSize(Std.int(bg.width), Std.int(bg.height));
		leftBar.updateHitbox();
		rightBar.setGraphicSize(Std.int(bg.width), Std.int(bg.height));
		rightBar.updateHitbox();
		if (_useRounded && _roundMask != null)
		{
			leftBar.pixels = _roundMask.clone();
			rightBar.pixels = _roundMask.clone();
			rightBar.color = FlxColor.BLACK;
			hollowShape = false;
		}
		else
		{
			// 回到贴图/自绘档：恢复实心填充位图（圆角遮罩不再生效）
			leftBar.pixels = new BitmapData(Std.int(bg.width), Std.int(bg.height), true, 0xFFFFFFFF);
			rightBar.pixels = new BitmapData(Std.int(bg.width), Std.int(bg.height), true, 0xFFFFFFFF);
			rightBar.color = FlxColor.BLACK;
			hollowShape = false;
			checkForHollowShape();
		}
		regenerateClips();
	}

	// 运行时切换新旧血条样式（旧入口，供既有调用点；权威路径走 setStyle）
	public function setNewStyle(useNew:Bool):Void
	{
		if (_useNew == useNew || bg == null) return;
		_useNew = useNew;
		rebuildBars();
	}

	override function update(elapsed:Float) {
		var value:Null<Float> = FlxMath.remapToRange(FlxMath.bound(valueFunction(), bounds.min, bounds.max), bounds.min, bounds.max, 0, 100);
		percent = (value != null ? value : 0);

		// 新版血条：外框颜色跟随血量多的一方（玩家满血偏右/左，按 leftToRight 分辨玩家色）。
		// 读实例状态 _useNew（而非全局设置）：圆角档黑底不参与跟随，运行时切档也即时生效。
		if (_useNew && bg != null)
		{
			var playerColor:FlxColor = leftToRight ? leftColor : rightColor;
			var opponentColor:FlxColor = leftToRight ? rightColor : leftColor;
			bg.color = (percent >= 50) ? playerColor : opponentColor;
		}

		super.update(elapsed);
	}
	
	public function setBounds(min:Float, max:Float)
	{
		bounds.min = min;
		bounds.max = max;
	}

	public function setColors(left:FlxColor, right:FlxColor)
	{
		leftColor = left;
		rightColor = right;
		leftBar.color = left;
		rightBar.color = right;
	}

	public function updateBar()
	{
		if(leftBar == null || rightBar == null) return;

		leftBar.setPosition(bg.x, bg.y);
		rightBar.setPosition(bg.x, bg.y);

		var leftSize:Float = 0;
		if(leftToRight) leftSize = FlxMath.lerp(0, barWidth, percent / 100);
		else leftSize = FlxMath.lerp(0, barWidth, 1 - percent / 100);

		leftBar.clipRect.width = leftSize;
		leftBar.clipRect.height = barHeight;
		leftBar.clipRect.x = barOffset.x;
		leftBar.clipRect.y = barOffset.y;

		rightBar.clipRect.width = barWidth - leftSize;
		rightBar.clipRect.height = barHeight;
		rightBar.clipRect.x = barOffset.x + leftSize;
		rightBar.clipRect.y = barOffset.y;

		barCenter = leftBar.x + leftSize + barOffset.x;

		// flixel is retarded
		leftBar.clipRect = leftBar.clipRect;
		rightBar.clipRect = rightBar.clipRect;
	}

	public function regenerateClips()
	{
		if(leftBar != null)
		{
			leftBar.setGraphicSize(Std.int(bg.width), Std.int(bg.height));
			leftBar.updateHitbox();
			leftBar.clipRect = new FlxRect(0, 0, Std.int(bg.width), Std.int(bg.height));
		}
		if(rightBar != null)
		{
			rightBar.setGraphicSize(Std.int(bg.width), Std.int(bg.height));
			rightBar.updateHitbox();
			rightBar.clipRect = new FlxRect(0, 0, Std.int(bg.width), Std.int(bg.height));
		}
		updateBar();
	}

	private function set_percent(value:Float)
	{
		var doUpdate:Bool = false;
		if(value != percent) doUpdate = true;
		percent = value;

		if(doUpdate) updateBar();
		return value;
	}

	private function set_leftToRight(value:Bool)
	{
		leftToRight = value;
		updateBar();
		return value;
	}

	private function set_barWidth(value:Int)
	{
		barWidth = value;
		regenerateClips();
		return value;
	}

	private function set_barHeight(value:Int)
	{
		barHeight = value;
		regenerateClips();
		return value;
	}

	// ---- Psych 0.6.3 (FlxBar) 兼容 API，供 0.6.3 及以下的旧模组脚本使用 ----

	// FlxBar 的 setRange，旧模组（Haxe）可能调用
	public function setRange(min:Float, max:Float)
	{
		setBounds(min, max);
	}

	// 0.6.3 的 healthBar.createFilledBar(emptyColor, fillColor)：
	// emptyColor 为未填充侧（对手）颜色，fillColor 为填充侧（玩家）颜色
	public function createFilledBar(empty:FlxColor, fill:FlxColor, showBorder:Bool = false, border:FlxColor = FlxColor.WHITE, borderSize:Int = 1)
	{
		setColors(empty, fill);
		this.borderSize = showBorder ? borderSize : 0;
		updateBar();
	}

	public var reversed(get, set):Bool;

	function get_reversed()
	{
		return !leftToRight;
	}

	function set_reversed(value:Bool)
	{
		leftToRight = !value;
		return value;
	}

	public var fillDirection(get, set):String;

	function get_fillDirection()
	{
		return leftToRight ? 'LEFT_TO_RIGHT' : 'RIGHT_TO_LEFT';
	}

	function set_fillDirection(value:String)
	{
		leftToRight = (value == 'LEFT_TO_RIGHT');
		return value;
	}

	// FlxBar 的圆角分割数，旧模组可能设置，此实现不需要分割所以无实际作用
	public var numDivisions:Int = 0;

	public var min(get, set):Float;
	public var max(get, set):Float;
	public var range(get, null):Float;
	public var value(get, set):Float;

	function get_min()
	{
		return bounds.min;
	}

	function set_min(newMin:Float)
	{
		bounds.min = newMin;
		return newMin;
	}

	function get_max()
	{
		return bounds.max;
	}

	function set_max(newMax:Float)
	{
		bounds.max = newMax;
		return newMax;
	}

	function get_range()
	{
		return bounds.max - bounds.min;
	}

	function get_value()
	{
		return valueFunction();
	}

	function set_value(newValue:Float)
	{
		percent = (newValue - bounds.min) / (bounds.max - bounds.min) * 100;
		return newValue;
	}

	private function set_borderSize(value:Int)
	{
		if(value != borderSize)
		{
			borderSize = value;
			// 圆角档几何由 buildBg 圆角分支固定（内缩 2px），脚本边框不改写它
			if(!hollowShape && !_useRounded)
			{
				barWidth = Std.int(bg.width - 6 - borderSize * 2);
				barHeight = Std.int(bg.height - 6 - borderSize * 2);
				barOffset.x = 3 + borderSize;
				barOffset.y = 3 + borderSize;
			}
		}
		return value;
	}

	private function checkForHollowShape():Void
	{
		if(bg == null || bg.pixels == null)
			return;

		var bitmap:BitmapData = bg.pixels;
		var w:Int = bitmap.width;
		var h:Int = bitmap.height;

		var alphaThreshold:Int = 50; // Alpha >= 50 的像素视为边框，阻止洪水填充
		var wallThreshold:Int = 250; // 阻挡填充扩展的实心墙

		var visited:openfl.Vector<Int> = new openfl.Vector<Int>(w * h, true);
		for(i in 0...visited.length) visited[i] = 0;

		var queue:Array<Int> = [];

		// 把所有边缘像素加入队列
		for(x in 0...w)
		{
			queue.push(x); // 顶行
			queue.push((h - 1) * w + x); // 底行
		}
		for(y in 1...h - 1)
		{
			queue.push(y * w); // 左列
			queue.push(y * w + (w - 1)); // 右列
		}

		var work:BitmapData = new BitmapData(w, h, true, 0x00000000);
		var idx:Int;
		var curX:Int, curY:Int;
		var pixelAlpha:Int;

		bitmap.lock();
		work.lock();

		// 第一遍：从边缘洪水填充，标记条外区域
		while(queue.length > 0)
		{
			idx = queue.pop();

			if(visited[idx] == 1) continue;

			curX = idx % w;
			curY = Std.int(idx / w);

			pixelAlpha = (bitmap.getPixel32(curX, curY) >> 24) & 0xFF;

			if(pixelAlpha >= alphaThreshold)
				continue; // 撞到边框，停止扩展

			visited[idx] = 1; // 透明/低透明：条外区域

			if(curX > 0) queue.push(idx - 1);
			if(curX < w - 1) queue.push(idx + 1);
			if(curY > 0) queue.push(idx - w);
			if(curY < h - 1) queue.push(idx + w);
		}

		// 第二遍：找到外壳内部未访问的透明区域，标记为填充区域
		var barQueue:Array<Int> = [];

		for(i in 0...w * h)
		{
			if(visited[i] == 0) // 在外壳内部
			{
				curX = i % w;
				curY = Std.int(i / w);
				pixelAlpha = (bitmap.getPixel32(curX, curY) >> 24) & 0xFF;

				if(pixelAlpha < alphaThreshold)
				{
					visited[i] = 2;
					barQueue.push(i);
				}
			}
		}

		while(barQueue.length > 0)
		{
			idx = barQueue.pop();

			curX = idx % w;
			curY = Std.int(idx / w);

			if(curX > 0 && visited[idx - 1] == 0 && (((bitmap.getPixel32(curX - 1, curY) >> 24) & 0xFF) <= wallThreshold))
			{
				visited[idx - 1] = 2;
				barQueue.push(idx - 1);
			}
			if(curX < w - 1 && visited[idx + 1] == 0 && (((bitmap.getPixel32(curX + 1, curY) >> 24) & 0xFF) <= wallThreshold))
			{
				visited[idx + 1] = 2;
				barQueue.push(idx + 1);
			}
			if(curY > 0 && visited[idx - w] == 0 && (((bitmap.getPixel32(curX, curY - 1) >> 24) & 0xFF) <= wallThreshold))
			{
				visited[idx - w] = 2;
				barQueue.push(idx - w);
			}
			if(curY < h - 1 && visited[idx + w] == 0 && (((bitmap.getPixel32(curX, curY + 1) >> 24) & 0xFF) <= wallThreshold))
			{
				visited[idx + w] = 2;
				barQueue.push(idx + w);
			}
		}

		for(x in 0...w)
		{
			for(y in 0...h)
			{
				idx = y * w + x;
				if(visited[idx] == 2)
					work.setPixel32(x, y, 0xFFFFFFFF);
				else
					work.setPixel32(x, y, 0x00000000);
			}
		}

		bitmap.unlock();
		work.unlock();

		var barBounds:Rectangle = work.getColorBoundsRect(0xFFFFFFFF, 0xFFFFFFFF, true);

		if(barBounds.width > 0 && barBounds.height > 0)
		{
			leftBar.pixels = work.clone();
			rightBar.pixels = work;
			hollowShape = true;

			barWidth = Std.int(bg.width);
			barHeight = Std.int(bg.height);
			barOffset.set(0, 0);

			leftBar.antialiasing = ClientPrefs.data.antialiasing;
			rightBar.antialiasing = ClientPrefs.data.antialiasing;
		}
		else
		{
			work.dispose();
		}
	}
}
