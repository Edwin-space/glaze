#!/usr/bin/env python3
"""Check Pages entry points and every local HTML asset/link, optionally over HTTP.

No credentials or external destinations are requested. Run from any directory:
  python3 script/check_public_site.py [--base-url https://edwin-space.github.io/glaze/]
"""
import argparse
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urljoin, urlsplit
from urllib.request import Request, urlopen


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.targets = []

    def handle_starttag(self, tag, attrs):
        for name, value in attrs:
            if name in {"href", "src"} and value:
                self.targets.append(value)


def check(base_url=None):
    site = Path(__file__).resolve().parents[1] / "site"
    required = {"index.html", "privacy/index.html", "support/index.html", "terms/index.html"}
    targets = set(required)
    for page in sorted(site.rglob("*.html")):
        parser = Links()
        parser.feed(page.read_text(encoding="utf-8"))
        for link in parser.targets:
            parsed = urlsplit(link)
            if parsed.scheme or parsed.netloc or not parsed.path:
                continue
            target = (page.parent / unquote(parsed.path)).resolve()
            if not target.is_relative_to(site):
                raise ValueError(f"Link escapes site/: {page.name}: {link}")
            if target.is_dir():
                target /= "index.html"
            if not target.is_file():
                raise FileNotFoundError(f"Broken local link: {page.relative_to(site)}: {link}")
            targets.add(target.relative_to(site).as_posix())
    for path in sorted(targets):
        if not (site / path).is_file():
            raise FileNotFoundError(path)
        if base_url:
            relative = path.removesuffix("index.html") if path.endswith("index.html") else path
            url = urljoin(base_url.rstrip("/") + "/", relative)
            request = Request(url, headers={"User-Agent": "Glaze-Pages-Healthcheck"})
            with urlopen(request, timeout=30) as response:
                if response.status != 200:
                    raise RuntimeError(f"{url}: HTTP {response.status}")
                content_type = response.headers.get("Content-Type", "")
                expected = "text/html" if path.endswith(".html") else (
                    "text/css" if path.endswith(".css") else "image/"
                )
                if expected not in content_type:
                    raise RuntimeError(f"{url}: unexpected Content-Type {content_type}")
                body = response.read()
                if not body or (expected == "text/html" and b"<main" not in body):
                    raise RuntimeError(f"{url}: empty or unexpected content")
            print(f"200 {url}")
    print(f"PASS: {len(targets)} Pages documents/assets")


if __name__ == "__main__":
    arguments = argparse.ArgumentParser()
    arguments.add_argument("--base-url")
    check(arguments.parse_args().base_url)
