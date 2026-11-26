"""Push delivery. FCM delivers to Android directly and to iOS through APNs."""
import asyncio
import logging
from dataclasses import dataclass, field
from typing import Protocol

log = logging.getLogger(__name__)

FCM_BATCH = 500  # FCM multicast limit


@dataclass
class Push:
    tokens: list[str]
    title: str
    body: str
    data: dict[str, str]
    thread_id: str  # groups a match's notifications together on iOS


class PushSender(Protocol):
    async def send(self, push: Push) -> list[str]:
        """Send and return tokens that are permanently invalid (to be removed)."""
        ...


@dataclass
class LogSender:
    """Development/test sender: logs instead of calling FCM and remembers what it 'sent'."""

    sent: list[Push] = field(default_factory=list)

    async def send(self, push: Push) -> list[str]:
        self.sent.append(push)
        log.info("PUSH x%d [%s] %s | %s", len(push.tokens), push.data.get("type"), push.title, push.body)
        return []


class FcmSender:
    def __init__(self, credentials_file: str):
        # Imported lazily: firebase_admin pulls in heavy crypto deps we don't need in tests.
        import firebase_admin
        from firebase_admin import credentials, messaging

        self._messaging = messaging
        try:
            self._app = firebase_admin.get_app()
        except ValueError:
            self._app = firebase_admin.initialize_app(credentials.Certificate(credentials_file))

    async def send(self, push: Push) -> list[str]:
        invalid: list[str] = []
        for i in range(0, len(push.tokens), FCM_BATCH):
            batch = push.tokens[i:i + FCM_BATCH]
            invalid += await asyncio.to_thread(self._send_batch, batch, push)
        return invalid

    def _send_batch(self, tokens: list[str], push: Push) -> list[str]:
        m = self._messaging
        message = m.MulticastMessage(
            tokens=tokens,
            notification=m.Notification(title=push.title, body=push.body),
            data=push.data,
            android=m.AndroidConfig(
                priority="high",
                ttl=600,  # a goal alert is useless after 10 minutes
                notification=m.AndroidNotification(channel_id="match_events", sound="default"),
            ),
            apns=m.APNSConfig(
                headers={"apns-priority": "10", "apns-expiration": "0"},
                payload=m.APNSPayload(aps=m.Aps(sound="default", thread_id=push.thread_id)),
            ),
        )
        response = m.send_each_for_multicast(message, app=self._app)
        invalid = []
        for token, r in zip(tokens, response.responses):
            if r.success:
                continue
            if isinstance(r.exception, (m.UnregisteredError, m.SenderIdMismatchError)):
                invalid.append(token)
            else:
                log.warning("FCM send failed for one token: %s", r.exception)
        log.info("FCM sent %d/%d", response.success_count, len(tokens))
        return invalid


def build_sender(credentials_file: str) -> PushSender:
    if credentials_file:
        return FcmSender(credentials_file)
    log.warning("FIREBASE_CREDENTIALS_FILE not set - notifications will only be logged")
    return LogSender()
