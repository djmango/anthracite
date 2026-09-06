# SPDX-License-Identifier: LGPL-2.1-or-later
"""FreeCAD-embedded bridge assertions and local provider fixture for runtests.nu."""
import json
import os
from pathlib import Path
import sys
import tempfile
import traceback


def provider_fixture():
    def send(value):
        print(json.dumps(value), flush=True)

    for line in sys.stdin:
        message = json.loads(line)
        method = message.get("method")
        request = message.get("id")
        if method == "initialize":
            send({"id": request, "result": {"userAgent": "anthracite-smoke"}})
        elif method == "model/list":
            send({"id": request, "result": {"data": [], "nextCursor": None}})
        elif method in ("thread/start", "thread/resume"):
            send({"id": request, "result": {"thread": {"id": "smoke-thread"}}})
        elif method == "turn/start":
            send({"id": request, "result": {"turn": {"id": "smoke-turn"}}})
            send({"id": 9001, "method": "item/tool/call", "params": {
                "tool": "freecad", "arguments": {"code":
                    "box = doc.addObject('Part::Box', 'BridgeBox')\nbox.Length = 12\nbox.Width = 8\nbox.Height = 5\ncad.render_views(width=256, height=192)"}}})
        elif request == 9001:
            result = json.loads(message["result"]["contentItems"][0]["text"])
            assert result["ok"], result
            images = message["result"]["contentItems"][1:]
            assert len(images) == 4, images
            assert all(image["type"] == "inputImage" and image["imageUrl"].startswith("data:image/png;base64,") for image in images)
            assert [view["view"] for view in result["observation"]["renders"]] == ["axonometric", "front", "right", "top"]
            send({"id": 9002, "method": "item/tool/call", "params": {
                "tool": "freecad", "arguments": {"code":
                    "doc.getObject('BridgeBox').Length = 99\ndoc.recompute()\n"
                    "doc.addObject('Part::Box', 'MustRollback')\nraise RuntimeError('smoke rollback')"}}})
        elif request == 9002:
            result = json.loads(message["result"]["contentItems"][0]["text"])
            assert not result["ok"] and result["rolledBack"], result
            send({"method": "turn/completed", "params": {
                "turn": {"id": "smoke-turn", "status": "completed"}}})


if len(sys.argv) > 1 and sys.argv[1] == "app-server":
    provider_fixture()
    sys.exit(0)


try:
    if os.environ.get("ANTHRACITE_SMOKE") != "1":
        raise RuntimeError("Run this test through just test with an isolated profile")
    import FreeCAD as App
    import FreeCADGui as Gui
    from PySide6 import QtCore, QtWidgets, QtQuickWidgets

    fixture_directory = tempfile.TemporaryDirectory(prefix="anthracite-provider-smoke-")
    python = Path(os.environ.get("ANTHRACITE_PYTHON", str(Path(sys.prefix) / "bin/python3")))
    if not python.is_file():
        raise RuntimeError(f"Packaged Python interpreter missing: {python}")
    fixture = Path(fixture_directory.name) / "codex-fixture"
    fixture.write_text(f"#!{python}\n" + Path(__file__).read_text())
    fixture.chmod(0o700)
    preferences = App.ParamGet("User parameter:BaseApp/Preferences/Mod/Anthracite")
    preferences.SetString("CodexBinary", str(fixture))
    document = App.newDocument("AnthraciteBridgeSmoke")
    dock = Gui.getMainWindow().findChild(QtWidgets.QDockWidget, "AnthraciteSidebar")
    quick = dock.findChild(QtQuickWidgets.QQuickWidget)
    controller = quick.rootContext().contextProperty("anthraciteController")
    controller.selectProvider("codex")
    submitted = False
    journal = Path(os.environ["XDG_STATE_HOME"]) / "anthracite/anthracite.events.jsonl"

    def check_result():
        global submitted
        try:
            if not submitted:
                if controller.property("status") == "Ready" and controller.property("currentThreadId"):
                    controller.submit("Run the deterministic native bridge test")
                    submitted = True
                return
            if not journal.exists():
                return
            text = journal.read_text()
            if not text.endswith("\n"):
                return
            lines = text.splitlines()
            results = [record["payload"] for record in map(json.loads, lines)
                       if record["type"] == "tool.result"]
            if len(results) < 2:
                return
            assert [result["status"] for result in results] == ["committed", "rolled_back"], results
            assert document.getObject("MustRollback") is None
            box = document.getObject("BridgeBox")
            assert box.Shape.isValid() and abs(box.Shape.Volume - 480) < 1e-6
            timer.stop()
            App.closeDocument(document.Name)
            print("ANTHRACITE_BRIDGE_SMOKE_OK", flush=True)
            QtWidgets.QApplication.instance().quit()
        except BaseException:
            traceback.print_exc()
            os._exit(1)

    def timeout():
        print("Native bridge smoke test timed out", file=sys.stderr, flush=True)
        os._exit(1)

    timer = QtCore.QTimer()
    timer.timeout.connect(check_result)
    timer.start(100)
    QtCore.QTimer.singleShot(60000, timeout)
except BaseException:
    traceback.print_exc()
    os._exit(1)
