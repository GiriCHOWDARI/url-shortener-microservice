from sqlalchemy import Column, Integer, String, DateTime
from app.core.database import Base
class ClickEvent(Base):
    __tablename__ = "click_events"
    id = Column(Integer, primary_key=True, index=True)
    short_code = Column(String, index=True, nullable=False)
    timestamp = Column(DateTime, nullable=False)
    ip_address = Column(String, nullable=True)
    user_agent = Column(String, nullable=True)
    referrer = Column(String, nullable=True)
