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
            inputs = message['params']['input']
            assert inputs[0]['type'] == 'text' and 'Attached file' in inputs[0]['text'], inputs
            assert inputs[1]['type'] == 'image' and inputs[1]['url'].startswith('data:image/png;base64,'), inputs
            send({"id": request, "result": {"turn": {"id": "smoke-turn"}}})
            send({"id": 9001, "method": "item/tool/call", "params": {
                "tool": "freecad", "arguments": {"code":
                    "box = doc.addObject('Part::Box', 'BridgeBox')\nbox.Length = 12\nbox.Width = 8\nbox.Height = 5\n"
                    "cad.verify([{'object':'BridgeBox','metric':'size_mm','expected':[12,8,5],'tolerance':0.001}])\n"
                    "cad.render_views(width=640, height=480, labels=True, axes=True, dimensions=True, highlight_changed=True)"}}})
        elif request == 9001:
            send({"method": "item/agentMessage/delta", "params": {
                "itemId": "progress", "delta": "Intermediate update: checking the box."}})
            result = json.loads(message["result"]["contentItems"][0]["text"])
            assert result["ok"], result
            assert result['verification'][0]['status'] == 'pass', result
            assert result['observation']['renders'][0]['annotations']['items'][0]['reference']['object'] == 'BridgeBox'
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
            send({"id": 9003, "method": "item/tool/call", "params": {
                "tool": "freecad", "arguments": {"code": "cad.action('Resize bridge box')\ndoc.getObject('BridgeBox').Length = 20"}}})
        elif request in (9003, 9004):
            result = json.loads(message["result"]["contentItems"][0]["text"])
            assert result["ok"], result
            assert result['observation']['visualFeedback']['status'] == 'captured', result
            images = message['result']['contentItems'][1:]
            assert len(images) == 2 and all(image['type'] == 'inputImage' for image in images)
            assert all(view['automatic'] for view in result['observation']['renders'])
            direction = "undo" if request == 9003 else "redo"
            entry = result["history"][direction]
            assert entry, result
            source = f"cad.{direction}(action={entry['action']!r}, revision={entry['revision']})"
            send({"id": request + 1, "method": "item/tool/call", "params": {
                "tool": "freecad", "arguments": {"code": source}}})
        elif request == 9005:
            result = json.loads(message["result"]["contentItems"][0]["text"])
            assert result["ok"], result
            send({"method": "item/agentMessage/delta", "params": {
                "itemId": "final", "delta": "Created the editable box."}})
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
    App.ParamGet("User parameter:BaseApp/Preferences/NotificationArea").SetBool(
        "NotificationAreaEnabled", False)
    from PySide6 import QtCore, QtWidgets, QtQuickWidgets, QtGui
    QtCore.QCoreApplication.sendPostedEvents(None, QtCore.QEvent.DeferredDelete)

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
    dock.show()
    quick = dock.findChild(QtQuickWidgets.QQuickWidget)
    controller = quick.rootContext().contextProperty("anthraciteController")
    controller.selectProvider("codex")
    submitted = False
    expanded = False
    replay_phase = "live"
    saved_thread = ""
    saved_work = None
    saved_attachments = None
    drafted_while_running = False
    def prepare_followup():
        global drafted_while_running
        if controller.property('busy') and not controller.property('submitting') and not drafted_while_running:
            composer = quick.rootObject().findChild(QtCore.QObject, 'AnthraciteComposer')
            assert composer.property('enabled'), 'Composer is disabled during execution'
            controller.setDraft('Next: make the wall thinner')
            drafted_while_running = True
    controller.busyChanged.connect(prepare_followup)
    journal = Path(os.environ["XDG_STATE_HOME"]) / "anthracite/anthracite.events.jsonl"

    def check_result():
        global submitted, expanded, replay_phase, saved_thread, saved_work, saved_attachments
        try:
            if replay_phase == 'attaching':
                if not controller.property('processingAttachments'):
                    saved_attachments = controller.property('attachments')
                    assert len(saved_attachments) == 2, saved_attachments
                    controller.setDraft('Run the deterministic native bridge test')
                    saved_thread = controller.property('currentThreadId')
                    replay_phase = 'draft-new'
                    controller.newThread()
                return
            if replay_phase == 'draft-new':
                if controller.property('status') == 'Ready' and controller.property('currentThreadId') != saved_thread:
                    assert not controller.property('attachments')
                    controller.selectThread(saved_thread)
                    replay_phase = 'draft-back'
                return
            if replay_phase == 'draft-back':
                if controller.property('status') == 'Ready' and controller.property('currentThreadId') == saved_thread:
                    assert controller.property('attachments') == saved_attachments
                    assert controller.property('draft') == 'Run the deterministic native bridge test'
                    assert dock.grab().save(str(Path(__file__).resolve().parent.parent / 'build/test-results/composer.png'))
                    controller.submit(controller.property('draft'))
                    submitted = True
                    replay_phase = 'live'
                return
            if replay_phase == "new":
                if controller.property("currentThreadId") != saved_thread and controller.property("status") == "Ready":
                    controller.selectThread(saved_thread)
                    replay_phase = "replay"
                return
            if not submitted:
                if controller.property("status") == "Ready" and controller.property("currentThreadId"):
                    image_path = Path(fixture_directory.name) / 'input.png'
                    image = QtGui.QImage(48, 32, QtGui.QImage.Format_RGB32)
                    image.fill(QtGui.QColor('blue'))
                    assert image.save(str(image_path))
                    file_path = Path(fixture_directory.name) / 'instructions.txt'
                    file_path.write_text('Build an editable box')
                    controller.attachFile(str(image_path))
                    controller.attachFile(str(file_path))
                    replay_phase = 'attaching'
                return
            if not journal.exists():
                return
            text = journal.read_text()
            if not text.endswith("\n"):
                return
            lines = text.splitlines()
            results = [record["payload"] for record in map(json.loads, lines)
                       if record["type"] == "tool.result"]
            if len(results) < 5:
                return
            model = controller.property("messages")
            roles = {bytes(name).decode(): role for role, name in model.roleNames().items()}
            rows = [{name: model.data(model.index(row, 0), role) for name, role in roles.items()}
                    for row in range(model.rowCount())]
            work = [row for row in rows if row['kind'] == 'work']
            if not work:
                return
            assert len(work) == 1, rows
            assert not controller.property('attachments'), 'Sent attachments were not cleared'
            user_images = [row['body'] for row in rows if row['kind'] == 'image']
            assert user_images == [saved_attachments[0]['dataUrl']], 'Input images lost in live/replayed timeline'
            assert work[0]['body'] == 'Created the editable box.', work
            assert drafted_while_running, 'No editable composer during the run'
            assert controller.property('draft') == 'Next: make the wall thinner', 'Run completion or replay erased the next draft'
            assert work[0]['author'].startswith('Worked for ') and work[0]['author'].endswith('s'), work
            def visual_items(item):
                yield item
                for child in item.childItems():
                    yield from visual_items(child)
            items = list(visual_items(quick.rootObject()))
            summaries = [item for item in items if item.objectName() == 'workSummary']
            if not summaries:
                return
            if not expanded:
                assert not work[0]['entries'], 'Collapsed work eagerly transported its images'
                assert not summaries[0].property('activityExpanded')
                summaries[0].toggleWork()
                expanded = True
                return
            entries = work[0]['entries']
            if len(entries) < work[0]['entryCount']:
                model.loadDetails(work[0]['entryId'])
                return
            assert any(entry['body'] == 'Intermediate update: checking the box.' for entry in entries)
            assert any(entry['body'].startswith('freecad\n') for entry in entries)
            images = [entry['body'] for entry in entries if entry['kind'] == 'image']
            observations = [record['payload'] for record in map(json.loads, lines)
                            if record['type'] == 'tool.observation']
            expected_images = [image for observation in observations for image in observation.get('images', [])]
            assert len(images) == 10 and images == expected_images
            rendered = [item for item in items if item.objectName() == 'workImage'
                        and item.property('source').toString()]
            assert len(rendered) == len(expected_images), [(item.property('source').toString()[:40], item.property('visible')) for item in rendered]
            assert [item.property('source').toString() for item in rendered] == images
            assert all(item.property('height') > 0 for item in rendered)
            capture = Path(os.environ['ANTHRACITE_TEST_LAUNCHER']).parent.parent / 'build/test-results/thread-expanded.png'
            assert dock.grab().save(str(capture))
            if replay_phase == "live":
                saved_thread = controller.property("currentThreadId")
                saved_work = work[0]
                replay_phase = "new"
                expanded = False
                controller.newThread()
                return
            assert work[0]['body'] == saved_work['body']
            assert work[0]['author'] == saved_work['author']
            assert work[0]['entries'] == saved_work['entries']
            assert [result["status"] for result in results] == ["committed", "rolled_back", "committed", "committed", "committed"], results
            assert document.getObject("MustRollback") is None
            box = document.getObject("BridgeBox")
            assert box.Shape.isValid() and abs(box.Shape.Volume - 800) < 1e-6
            timer.stop()
            App.closeDocument(document.Name)
            # Release the inspected QML delegates while PySide is still alive,
            # not during macOS's late QApplication/Python teardown.
            def finish():
                Gui.runCommand("Anthracite_ReloadSidebar")
                QtCore.QCoreApplication.sendPostedEvents(None, QtCore.QEvent.DeferredDelete)
                print("ANTHRACITE_BRIDGE_SMOKE_OK", flush=True)
                QtWidgets.QApplication.instance().quit()
            QtCore.QTimer.singleShot(0, finish)
        except BaseException:
            traceback.print_exc()
            os._exit(1)

    def timeout():
        os.write(2, f"Bridge phase: {replay_phase}; status: {controller.property('status')}; expanded: {expanded}\n".encode())
        model = controller.property("messages")
        rows = [(model.data(model.index(row, 0), 259),
                              str(model.data(model.index(row, 0), 257)))
                             for row in range(model.rowCount())]
        os.write(2, f"Chat rows: {rows}; QML: {quick.source().toString()}; visible: {dock.isVisible()}\n".encode())
        print("Native bridge smoke test timed out", file=sys.stderr, flush=True)
        os._exit(1)

    timer = QtCore.QTimer()
    timer.timeout.connect(check_result)
    timer.start(100)
    QtCore.QTimer.singleShot(60000, timeout)
except BaseException:
    traceback.print_exc()
    os._exit(1)
