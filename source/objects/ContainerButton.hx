package objects;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;

/**
 * 系统域圆角按钮（MD3 令牌；容器页 / 引擎切换页共用）。
 *
 * 从 `states.ContainersMenuState` 的模块内私有类提出来：多引擎切换页要用同一个控件，
 * 而 UI-DESIGN §0 明确要求「同一语义的控件在两处长得不一样就是 bug」——
 * 复制一份改改颜色是明确禁止的做法，所以提成独立模块复用。
 */
class ContainerButton extends FlxSpriteGroup
{
	public var onClick:Void->Void;
	public var spr:FlxSprite;
	/** 按钮文字：开关类按钮需要运行期改文案/配色。 */
	public var label:FlxText;
	public var btnW:Float;
	public var btnH:Float;
	var hovered:Bool = false;
	var awake:Bool = false;
	var lastX:Float = 0;
	var lastY:Float = 0;
	var enabled:Bool = true;

	public function new(x:Float, y:Float, w:Float, h:Float, text:String, ?cb:Void->Void)
	{
		super(x, y);
		onClick = cb;
		btnW = w;
		btnH = h;

		// unique = true：同尺寸同色会命中缓存里同一张 BitmapData，原地重绘会串图（UI-DESIGN §3）
		spr = new FlxSprite().makeGraphic(Std.int(w), Std.int(h), FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRoundRect(spr, 0, 0, w, h, 14, 14, 0x66161622);
		FlxSpriteUtil.drawRoundRect(spr, 1, 1, w - 2, h - 2, 14, 14, FlxColor.TRANSPARENT, {color: 0x8CFFFFFF, thickness: 1.5});
		spr.alpha = 0.85;
		spr.scrollFactor.set();
		add(spr);

		label = new FlxText(0, 0, Std.int(w), text, 18);
		label.setFormat(Paths.font('future.ttf'), 18, 0xFFCFCFDC, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		label.borderSize = 1.5;
		label.textField.height = 44;
		label.scrollFactor.set();
		label.y = 12;
		add(label);

		scrollFactor.set();
		lastX = FlxG.mouse.screenX;
		lastY = FlxG.mouse.screenY;
	}

	public function setEnabled(v:Bool):Void
	{
		enabled = v;
		alpha = v ? 1 : 0.45;
	}

	public function over(mx:Float, my:Float):Bool
	{
		if (!visible || !enabled) return false;
		return mx >= x && mx <= x + btnW && my >= y && my <= y + btnH;
	}

	public function setHovered(mx:Float, my:Float)
	{
		if (!awake)
		{
			var dx:Float = mx - lastX;
			var dy:Float = my - lastY;
			if (dx * dx + dy * dy < 100) return;
			awake = true;
		}
		lastX = mx;
		lastY = my;

		var v:Bool = over(mx, my);
		if (hovered == v) return;
		hovered = v;
		spr.color = v ? 0xFFFFFFFF : 0xFFD5D9DF;
		spr.alpha = v ? 1 : 0.85;
	}
}
