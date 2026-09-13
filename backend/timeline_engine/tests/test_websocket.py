"""WebSocket live timeline streaming tests."""

import json

import pytest
from starlette.testclient import TestClient

from src.main import app
from src.timeline.router import ws_manager


def test_websocket_ping_pong():
    with TestClient(app) as client:
        with client.websocket_connect("/ws/live-timeline?case_id=CASE-001") as websocket:
            websocket.send_text("ping")
            data = websocket.receive_text()
            assert json.loads(data) == {"type": "pong"}


def test_websocket_missing_case_id_rejected():
    """Verify that connecting without case_id is rejected with WS 1008 policy violation."""
    with TestClient(app) as client:
        with pytest.raises(Exception) as exc_info:
            with client.websocket_connect("/ws/live-timeline"):
                pass
        assert "1008" in str(exc_info.value) or "WebSocketDisconnect" in exc_info.typename


@pytest.mark.asyncio
async def test_websocket_broadcast():
    with TestClient(app) as client:
        with client.websocket_connect("/ws/live-timeline?case_id=CASE-001") as websocket:
            # Broadcast message through manager for CASE-001
            test_msg = {
                "type": "timeline_event",
                "case_id": "CASE-001",
                "data": {"test_id": "123"},
            }
            await ws_manager.broadcast(test_msg)

            data = websocket.receive_text()
            received = json.loads(data)
            assert received["type"] == "timeline_event"
            assert received["data"]["test_id"] == "123"


@pytest.mark.asyncio
async def test_websocket_case_isolation():
    """Verify that clients only receive events for their subscribed case_id."""
    with TestClient(app) as client:
        with (
            client.websocket_connect("/ws/live-timeline?case_id=CASE-A") as ws_a,
            client.websocket_connect("/ws/live-timeline?case_id=CASE-B") as ws_b,
        ):
            # Send message for CASE-A only
            msg_a = {
                "type": "timeline_event",
                "case_id": "CASE-A",
                "data": {"secret": "case_a_only"},
            }
            await ws_manager.broadcast(msg_a)

            data_a = json.loads(ws_a.receive_text())
            assert data_a["data"]["secret"] == "case_a_only"

            # Ping-pong on ws_b to ensure queue didn't have the message
            ws_b.send_text("ping")
            pong = json.loads(ws_b.receive_text())
            assert pong == {"type": "pong"}
