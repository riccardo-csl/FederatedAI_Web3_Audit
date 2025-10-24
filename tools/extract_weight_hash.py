import sys
import json


def main() -> int:
    s = sys.stdin.read().strip()
    try:
        obj = json.loads(s)
        if isinstance(obj, str):
            obj = json.loads(obj)
        if isinstance(obj, dict):
            print(obj.get("weight_hash", ""))
            return 0
        print("")
        return 1
    except Exception:
        print("")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

