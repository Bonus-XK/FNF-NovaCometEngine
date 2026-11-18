package bridge;

/** 编辑器边界统一入口（第④大类 ②）。
 *  主流程（states 根 / backend / objects）不再 import states.editors.*；进入编辑器的路径全部收敛到本类。
 *  本类内部用**全限定名**引用编辑器类 → 连本类也不产生 `import states.editors.*`。
 *  可复核：python3 tools/boundary/editor_census.py → 主流程 import 编辑器类 5 → 0。 */
class EditorBridge
{
	/** 本次会话请求经典编谱器（官方 UI 版 Help → Classic Editor 设置）。 */
	public static var classicEditorRequested:Bool = false;

	/** 打开编谱器：默认官方 UI 版；经典版仍可通过 Help 菜单/存档位回退。 */
	public static function openChartEditor():Void
	{
		if (classicEditorRequested || flixel.FlxG.save.data.classicChartEditor == true)
			backend.MusicBeatState.switchState(new states.editors.ChartingState());
		else
			backend.MusicBeatState.switchState(new states.editors.OfficialChartEditorState());
	}

	/** 打开人物编辑器（原 PlayState:2193 的 `new CharacterEditorState(SONG.player2)`）。 */
	public static function openCharacterEditor(character:String):Void
		backend.MusicBeatState.switchState(new states.editors.CharacterEditorState(character));

	/** 打开主编辑器菜单（原 MainMenuState:387 的 `new MasterEditorMenu()`）。 */
	public static function openMasterEditor():Void
		backend.MusicBeatState.switchState(new states.editors.MasterEditorMenu());

	/** 编谱器音符类型表（只读；原 PlayState:1806 / NoteChartDomain:525 的 `ChartingState.noteTypeList`）。 */
	public static function noteTypeList():Array<String>
		return states.editors.ChartingState.noteTypeList;
}
