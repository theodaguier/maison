#!/usr/bin/env python3
"""Builds Maison/Resources/IntegrationCategories.json from Home Assistant's own data.

The categories are those of each integration's documentation page (`ha_categories`), and the
popularity is the number of installations in Home Assistant's public analytics. Nothing is written
by hand, so no brand is chosen by Maison.

    git clone --depth 1 --filter=blob:none --sparse https://github.com/home-assistant/home-assistant.io.git docs
    git -C docs sparse-checkout set source/_integrations
    ./ci/integration-categories.py docs/source/_integrations
"""

import json
import os
import re
import sys
import urllib.request

ANALYTICS = "https://analytics.home-assistant.io/data.json"
OUTPUT = os.path.join(os.path.dirname(__file__), "..", "Maison", "Resources", "IntegrationCategories.json")


def front_matter(path):
    with open(path, encoding="utf-8") as file:
        match = re.match(r"---\n(.*?)\n---", file.read(), re.S)
    return match.group(1) if match else ""


def listed(matter, key):
    block = re.search(rf"^{key}:\n((?:\s+- .*\n?)+)", matter, re.M)
    return [item.strip().strip("'\"") for item in re.findall(r"- (.+)", block.group(1))] if block else []


def main(pages):
    request = urllib.request.Request(ANALYTICS, headers={"User-Agent": "maison-ci"})
    with urllib.request.urlopen(request) as response:
        installs = json.load(response)["current"]["integrations"]
    result = {}
    for name in sorted(os.listdir(pages)):
        if not name.endswith(".markdown"):
            continue
        matter = front_matter(os.path.join(pages, name))
        domain = re.search(r"^ha_domain: (\S+)", matter, re.M)
        if not domain or not re.search(r"^ha_config_flow: true", matter, re.M):
            continue
        categories = listed(matter, "ha_categories")
        if categories:
            result[domain.group(1)] = {"c": categories, "n": installs.get(domain.group(1), 0)}
    with open(OUTPUT, "w", encoding="utf-8") as file:
        json.dump(result, file, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        file.write("\n")
    print(f"{len(result)} integrations")


if __name__ == "__main__":
    main(sys.argv[1])
