#!/usr/bin/env python3
import sys
import os
import json
import re
import datetime
import subprocess
import urllib.request

STATE_DIR = os.path.expanduser("~/.local/state")
CONFIG_FILE = os.path.join(STATE_DIR, "calendar_config.json")
LOCAL_EVENTS_FILE = os.path.join(STATE_DIR, "calendar_local.json")
OUTPUT_FILE = os.path.join(STATE_DIR, "calendar_events.json")

def parse_ics_date(val):
    if not val:
        return None
    val = val.strip().replace("Z", "")
    # Format: YYYYMMDD or YYYYMMDDTHHMMSS
    try:
        if "T" in val:
            return datetime.datetime.strptime(val[:15], "%Y%m%dT%H%M%S")
        else:
            return datetime.datetime.strptime(val[:8], "%Y%m%d")
    except Exception:
        return None

def fetch_ics_events(url):
    events = []
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'CaelestiaCalendar/1.0'})
        with urllib.request.urlopen(req, timeout=5) as resp:
            content = resp.read().decode('utf-8', errors='ignore')
        
        now = datetime.datetime.now()
        horizon = now + datetime.timedelta(days=14)

        raw_events = content.split("BEGIN:VEVENT")
        for block in raw_events[1:]:
            end_pos = block.find("END:VEVENT")
            if end_pos != -1:
                block = block[:end_pos]
            
            summary = ""
            start_dt = None
            end_dt = None
            location = ""

            for line in block.splitlines():
                line = line.strip()
                if line.startswith("SUMMARY:"):
                    summary = line[8:].replace("\\,", ",").replace("\\n", " ")
                elif line.startswith("DTSTART"):
                    parts = line.split(":", 1)
                    if len(parts) == 2:
                        start_dt = parse_ics_date(parts[1])
                elif line.startswith("DTEND"):
                    parts = line.split(":", 1)
                    if len(parts) == 2:
                        end_dt = parse_ics_date(parts[1])
                elif line.startswith("LOCATION:"):
                    location = line[9:].replace("\\,", ",")

            if summary and start_dt:
                # Include today and upcoming 14 days
                if start_dt.date() >= (now.date() - datetime.timedelta(days=1)) and start_dt.date() <= horizon.date():
                    time_str = start_dt.strftime("%I:%M %p").lstrip("0") if "T" in block else "All Day"
                    events.append({
                        "title": summary,
                        "date": start_dt.strftime("%Y-%m-%d"),
                        "dateDisplay": start_dt.strftime("%a, %b %d"),
                        "time": time_str,
                        "location": location,
                        "isToday": (start_dt.date() == now.date()),
                        "sortKey": start_dt.isoformat(),
                        "source": "google"
                    })
    except Exception as e:
        sys.stderr.write(f"Error fetching ICS: {e}\n")
    return events

def fetch_khal_events():
    events = []
    try:
        out = subprocess.check_output(
            ["khal", "list", "--format", "{start-date}|{start-time}|{title}|{location}", "today", "14d"],
            stderr=subprocess.DEVNULL,
            text=True
        )
        now = datetime.datetime.now()
        for line in out.splitlines():
            parts = line.strip().split("|")
            if len(parts) >= 3:
                d_str, t_str, title = parts[0], parts[1], parts[2]
                loc = parts[3] if len(parts) > 3 else ""
                try:
                    dt = datetime.datetime.strptime(d_str, "%d/%m/%Y")
                    iso_date = dt.strftime("%Y-%m-%d")
                    events.append({
                        "title": title,
                        "date": iso_date,
                        "dateDisplay": dt.strftime("%a, %b %d"),
                        "time": t_str if t_str else "All Day",
                        "location": loc,
                        "isToday": (dt.date() == now.date()),
                        "sortKey": f"{iso_date}T{t_str}",
                        "source": "khal"
                    })
                except Exception:
                    pass
    except Exception:
        pass
    return events

def fetch_local_events():
    events = []
    if os.path.exists(LOCAL_EVENTS_FILE):
        try:
            with open(LOCAL_EVENTS_FILE, "r") as f:
                data = json.load(f)
                now = datetime.datetime.now()
                for item in data:
                    try:
                        dt = datetime.datetime.strptime(item.get("date", ""), "%Y-%m-%d")
                        events.append({
                            "title": item.get("title", "Event"),
                            "date": item.get("date", ""),
                            "dateDisplay": dt.strftime("%a, %b %d"),
                            "time": item.get("time", "All Day"),
                            "location": item.get("location", ""),
                            "isToday": (dt.date() == now.date()),
                            "sortKey": f"{item.get('date')}T{item.get('time')}",
                            "source": "local",
                            "id": item.get("id")
                        })
                    except Exception:
                        pass
        except Exception:
            pass
    return events

def main():
    os.makedirs(STATE_DIR, exist_ok=True)
    config = {}
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r") as f:
                config = json.load(f)
        except Exception:
            config = {}

    all_events = []
    ics_url = config.get("ics_url", "").strip()
    if ics_url:
        all_events.extend(fetch_ics_events(ics_url))

    all_events.extend(fetch_khal_events())
    all_events.extend(fetch_local_events())

    # Sort events by date/time
    all_events.sort(key=lambda x: x.get("sortKey", ""))

    with open(OUTPUT_FILE, "w") as f:
        json.dump(all_events, f, indent=2)

    print(json.dumps(all_events))

if __name__ == "__main__":
    main()
