import json
import os
import sys

def main():
    if len(sys.argv) < 2: return
    target_id = sys.argv[1]
    pref_path = os.path.expanduser("~/.local/share/org.localsend.localsend_app/shared_preferences.json")
    try:
        with open(pref_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        history_raw = data.get("flutter.ls_receive_history", [])
        history_parsed = []
        for item in history_raw:
            try: history_parsed.append(json.loads(item))
            except: pass
        history_filtered = [x for x in history_parsed if str(x.get("id")) != str(target_id)]
        history_filtered.sort(key=lambda x: x.get("timestamp", ""), reverse=True)
        history_filtered = history_filtered[:30]
        data["flutter.ls_receive_history"] = [json.dumps(x, separators=(',', ':'), ensure_ascii=False) for x in history_filtered]
        with open(pref_path, "w", encoding="utf-8") as f:
            json.dump(data, f, separators=(',', ':'), ensure_ascii=False)
    except Exception as e:
        with open("/tmp/ls_debug.log", "w") as log: log.write(str(e))
main()