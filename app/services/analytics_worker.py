import json
import asyncio
from datetime import datetime
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.analytics import ClickEvent
from app.services.cache import redis_client
from app.core.database import async_session

async def process_analytics():
    while True:
        try:
            # Read from Redis Stream (consumer group would be better, simple version)
            messages = await redis_client.xread({"analytics_stream": "0"}, count=10, block=1000)
            for stream, entries in messages:
                for msg_id, data in entries:
                    event = data
                    async with async_session() as db:
                        click = ClickEvent(
                            short_code=event["short_code"],
                            timestamp=datetime.fromisoformat(event["timestamp"]),
                            ip_address=event.get("ip_address"),
                            user_agent=event.get("user_agent"),
                            referrer=event.get("referrer")
                        )
                        db.add(click)
                        await db.commit()
                    # Acknowledge / delete message (simplified: trim stream)
            await asyncio.sleep(0.1)
        except Exception as e:
            print(f"Analytics worker error: {e}")
            await asyncio.sleep(5)