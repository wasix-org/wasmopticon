import json
import re
import sys
from pathlib import Path

site = Path(sys.argv[1])
payload = re.compile(r'(<script\b[^>]*\bid="__NUXT_DATA__"[^>]*>)(.*?)(</script>)', re.DOTALL)


def normalize(data):
    values = json.loads(data)
    timestamp = values[values[0]["prerenderedAt"]]
    if type(timestamp) is not int:
        raise ValueError("Nuxt prerenderedAt must reference an integer timestamp")
    normalized, count = re.subn(rf"(?<![0-9]){timestamp}(?![0-9])", "946684800000", data)
    if count != 1:
        raise ValueError("Nuxt prerender timestamp must appear once per payload")
    return normalized


for path in site.rglob("_payload.json"):
    path.write_text(normalize(path.read_text()))
for path in site.rglob("*.html"):
    text = path.read_text()
    updated = payload.sub(lambda match: match[1] + normalize(match[2]) + match[3], text)
    if updated != text:
        path.write_text(updated)
