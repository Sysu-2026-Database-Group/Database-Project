"""Independent bounded expiry worker. No employee identity and no web thread."""
import argparse
import json
import os
import time
from datetime import datetime, timezone

from .dao import EmployeeDAO
from .errors import AppError


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--once',action='store_true')
    parser.add_argument('--interval',type=int,default=60)
    parser.add_argument('--batch-size',type=int,default=100)
    args=parser.parse_args()
    if not 1<=args.interval<=3600 or not 1<=args.batch_size<=1000:
        parser.error('interval 1..3600, batch-size 1..1000')
    database=os.environ.get('BOOKSTORE_DATABASE','')
    if not database.startswith('ShiguangBookstoreWeek7') or not os.environ.get('BOOKSTORE_DB_TASK'):
        parser.error('Explicit Week7 database and task connection required')
    dao=EmployeeDAO({'task':os.environ['BOOKSTORE_DB_TASK']},expected_database=database)
    try:
        while True:
            try:
                count=dao.reservations_expire(args.batch_size)
                print(json.dumps(dict(time=datetime.now(timezone.utc).isoformat(),event='expiry',expired=count,status='success')),flush=True)
            except AppError as error:
                print(json.dumps(dict(time=datetime.now(timezone.utc).isoformat(),event='expiry',status='failure',code=error.code)),flush=True)
                if args.once:
                    return 1
            if args.once:
                return 0
            time.sleep(args.interval)
    except KeyboardInterrupt:
        return 0


if __name__=='__main__':
    raise SystemExit(main())
