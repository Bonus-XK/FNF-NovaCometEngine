package modcharting;

import flixel.graphics.tile.FlxDrawTrianglesItem.DrawData;
import openfl.geom.Vector3D;
import objects.Note;
import flixel.FlxStrip;

// 基于 FNF-Modcharting-Tools v1.0.1（TheZoroForce007，Apache-2.0）移植适配 NovaComet Engine。
// 长条网格：模表渲染器接管绘制时，用 FlxStrip 世界空间顶点替代引擎自绘的长条。

class SustainStrip extends FlxStrip
{
    private static final noteUV:Array<Float> = [
        0, 0, //top left
        1, 0, //top right
        0, 0.5, //half left
        1, 0.5, //half right
        0, 1, //bottom left
        1, 1 //bottom right
    ];
    private static final noteIndices:Array<Int> = [
        0, 1, 2, 1, 3, 2, 2, 3, 4, 3, 4, 5
        //makes 4 triangles
    ];

    private var daNote:Note;

    override public function new(daNote:Note)
    {
        this.daNote = daNote;
        daNote.alpha = 1;
        super(0, 0);

        // ⚠ tile 渲染下 FlxSprite.useFramePixels == false，且渲染器接管绘制后长条音符
        // 从未经 Note.draw() 生成 framePixels：updateFramePixels() 返回 null，
        // loadGraphic(null) 静默失败 → graphic == null → FlxStrip.draw() 首行直接 return
        // （四边形算得再准也全隐身）。改用音符所在图集 + 当前帧 UV：
        // 零额外纹理、与同图集三角形合批、RGB 染色 shader 仍作用于同一张图集。
        var frame = daNote.frame;
        if (daNote.graphic != null && frame != null && frame.uv != null)
        {
            graphic = daNote.graphic;
            var uv = frame.uv;
            // flixel 的 frame.uv 存 (x0, y0, x1, y1)：width/height 实为右/下边界
            var u0 = uv.x;
            var u1 = uv.width;
            var v0 = uv.y;
            var v1 = uv.height;
            var vm = (v0 + v1) * 0.5;
            var mappedUV:Array<Float> = [u0, v0, u1, v0, u0, vm, u1, vm, u0, v1, u1, v1];
            for (value in mappedUV)
            {
                uvtData.push(value);
                vertices.push(0);
            }
            antialiasing = daNote.antialiasing;
        }
        else
        {
            // 兜底：帧/图集不可用时按当前帧画一张独立位图，保证网格有纹理可采样
            if (frame != null)
                loadGraphic(frame.paint(), false, 0, 0, true);
            else
            {
                var pixels = daNote.updateFramePixels();
                if (pixels != null)
                    loadGraphic(pixels, false, 0, 0, true);
            }
            for (uv in noteUV)
            {
                uvtData.push(uv);
                vertices.push(0);
            }
        }
        shader = daNote.shader;
        for (ind in noteIndices)
            indices.push(ind);
    }

    public function constructVertices(noteData:NotePositionData, thisNotePos:Vector3D, nextHalfNotePos:NotePositionData, nextNotePos:NotePositionData, flipGraphic:Bool, reverseClip:Bool)
    {
        var yOffset = 2; //fix small gaps
        if (reverseClip)
            yOffset = -yOffset;

        var verts:Array<Float> = [];
        if (flipGraphic)
        {
            verts.push(nextNotePos.x);
            verts.push(nextNotePos.y + yOffset); //slight offset to fix small gaps
            verts.push(nextNotePos.x + (daNote.frameWidth * (1 / -nextNotePos.z) * noteData.scaleX));
            verts.push(nextNotePos.y + yOffset);

            verts.push(nextHalfNotePos.x);
            verts.push(nextHalfNotePos.y);
            verts.push(nextHalfNotePos.x + (daNote.frameWidth * (1 / -nextHalfNotePos.z) * noteData.scaleX));
            verts.push(nextHalfNotePos.y);

            verts.push(thisNotePos.x);
            verts.push(thisNotePos.y);
            verts.push(thisNotePos.x + (daNote.frameWidth * (1 / -thisNotePos.z) * nextNotePos.scaleX));
            verts.push(thisNotePos.y);
        }
        else
        {
            verts.push(thisNotePos.x);
            verts.push(thisNotePos.y);
            verts.push(thisNotePos.x + (daNote.frameWidth * (1 / -thisNotePos.z) * noteData.scaleX));
            verts.push(thisNotePos.y);

            verts.push(nextHalfNotePos.x);
            verts.push(nextHalfNotePos.y);
            verts.push(nextHalfNotePos.x + (daNote.frameWidth * (1 / -nextHalfNotePos.z) * noteData.scaleX));
            verts.push(nextHalfNotePos.y);

            verts.push(nextNotePos.x);
            verts.push(nextNotePos.y + yOffset); //slight offset to fix small gaps
            verts.push(nextNotePos.x + (daNote.frameWidth * (1 / -nextNotePos.z) * nextNotePos.scaleX));
            verts.push(nextNotePos.y + yOffset);
        }
        vertices = new DrawData(12, true, verts);
    }
}
