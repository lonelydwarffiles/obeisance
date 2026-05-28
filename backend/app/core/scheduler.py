from datetime import datetime

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from sqlalchemy import select

from app.db.database import AsyncSessionLocal
from app.db.models import RuleContract


scheduler = AsyncIOScheduler()


async def check_rule_contracts() -> None:
    now = datetime.utcnow()
    current_time = now.time()
    current_weekday = now.weekday()

    async with AsyncSessionLocal() as session:
        await session.execute(
            select(RuleContract).where(
                RuleContract.is_active.is_(True),
                RuleContract.deadline_time <= current_time,
                RuleContract.days_of_week.any(current_weekday),
            )
        )
        # TODO: evaluate completion state and apply Grace rewards/punishments.


scheduler.add_job(check_rule_contracts, "interval", minutes=1, id="check_rule_contracts", replace_existing=True)
