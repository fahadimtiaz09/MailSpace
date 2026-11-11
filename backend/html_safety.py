"""html_safety.py — makes an email's HTML safe to show (email "templates":
headers, footers, logos, colours, tables).

Only an allow-list of tags, attributes and CSS properties is kept. Everything
else is removed: scripts, iframes, forms, event handlers (onclick=...),
javascript: links, CSS url(...), <style> blocks, comments.

Uses only Python's standard library (no extra package to install).
"""
import html
import re
from html.parser import HTMLParser

MAX_HTML = 400_000  # characters kept after cleaning

ALLOWED_TAGS = {
    "a", "abbr", "b", "big", "blockquote", "br", "caption", "center", "code", "col",
    "colgroup", "dd", "del", "div", "dl", "dt", "em", "font", "h1", "h2", "h3", "h4",
    "h5", "h6", "hr", "i", "img", "ins", "li", "ol", "p", "pre", "q", "s", "small",
    "span", "strike", "strong", "sub", "sup", "table", "tbody", "td", "tfoot", "th",
    "thead", "tr", "tt", "u", "ul",
}
VOID_TAGS = {"br", "hr", "img", "col"}
NO_END_TAG = {"meta", "link", "base"}  # never have a closing tag

# Tags whose CONTENT is dropped too (not just the tag)
DROP_WITH_CONTENT = {
    "script", "style", "head", "title", "iframe", "frame", "frameset", "object",
    "embed", "noscript", "template", "svg", "math", "canvas", "audio", "video",
    "select", "textarea", "button", "applet", "base", "link", "meta",
}

COMMON_ATTRS = {"style", "align", "valign", "dir", "title", "width", "height", "bgcolor", "class"}
TAG_ATTRS = {
    "a": {"href"},
    "img": {"src", "alt", "border"},
    "table": {"border", "cellpadding", "cellspacing"},
    "td": {"colspan", "rowspan", "nowrap"},
    "th": {"colspan", "rowspan", "nowrap"},
    "col": {"span"},
    "colgroup": {"span"},
    "font": {"color", "size", "face"},
    "ol": {"start", "type"},
    "ul": {"type"},
    "li": {"value"},
    "blockquote": {"cite"},
}

SAFE_CSS = {
    "color", "background-color", "background", "font", "font-family", "font-size",
    "font-style", "font-weight", "line-height", "letter-spacing", "text-align",
    "text-decoration", "text-transform", "vertical-align", "white-space", "word-break",
    "word-wrap", "overflow-wrap", "width", "max-width", "min-width", "height",
    "max-height", "min-height", "margin", "margin-top", "margin-right", "margin-bottom",
    "margin-left", "padding", "padding-top", "padding-right", "padding-bottom",
    "padding-left", "border", "border-top", "border-right", "border-bottom",
    "border-left", "border-color", "border-style", "border-width", "border-radius",
    "border-collapse", "border-spacing", "display", "list-style", "list-style-type",
    "table-layout", "opacity",
}
BAD_CSS = re.compile(r"url\s*\(|expression|javascript:|behavior|-moz-binding|@import|\\|<|>", re.I)
SAFE_DISPLAY = {"block", "inline", "inline-block", "table", "table-row", "table-cell",
                "none", "flex", "list-item"}
DATA_IMAGE = re.compile(r"^data:image/(png|jpe?g|gif|webp);base64,[a-z0-9+/=\s]+$", re.I)
NUMBER = re.compile(r"^\d{1,4}%?$")


def clean_css(style):
    kept = []
    for part in style.split(";"):
        if ":" not in part:
            continue
        prop, value = part.split(":", 1)
        prop, value = prop.strip().lower(), value.strip()
        if prop not in SAFE_CSS or not value or BAD_CSS.search(value):
            continue
        if prop == "display" and value.lower() not in SAFE_DISPLAY:
            continue
        kept.append(f"{prop}: {value}")
    return "; ".join(kept)


def clean_url(url, for_image=False):
    url = (url or "").strip()
    low = re.sub(r"[\s\x00-\x1f]", "", url.lower())
    if low.startswith(("https://", "http://")):
        return url
    if not for_image and low.startswith("mailto:"):
        return url
    if for_image and DATA_IMAGE.match(url):
        return url
    return None  # javascript:, data:text/html, cid: that wasn't found, relative links...


class _Cleaner(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out = []
        self.stack = []          # open allowed tags
        self.skip_depth = 0      # >0 while inside <script>, <style>, ...

    # -- tags --
    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        if tag in NO_END_TAG:
            return
        if self.skip_depth:
            if tag in DROP_WITH_CONTENT:
                self.skip_depth += 1
            return
        if tag in DROP_WITH_CONTENT:
            self.skip_depth = 1
            return
        if tag not in ALLOWED_TAGS:
            return  # drop the tag, keep its text
        allowed = COMMON_ATTRS | TAG_ATTRS.get(tag, set())
        parts = []
        for name, value in attrs:
            name = (name or "").lower()
            if name not in allowed or value is None:
                continue
            if name == "style":
                value = clean_css(value)
            elif name == "href":
                value = clean_url(value)
            elif name == "src":
                value = clean_url(value, for_image=True)
            elif name in ("width", "height", "border", "cellpadding", "cellspacing",
                          "colspan", "rowspan", "span", "start", "value"):
                value = value.strip() if NUMBER.match(value.strip()) else None
            if value:
                parts.append(f' {name}="{html.escape(value, quote=True)}"')
        if tag == "a":
            parts.append(' target="_blank" rel="noopener noreferrer nofollow"')
        if tag == "img" and not any(p.startswith(" src=") for p in parts):
            return  # an image without a safe source is dropped
        self.out.append(f"<{tag}{''.join(parts)}>")
        if tag not in VOID_TAGS:
            self.stack.append(tag)

    def handle_startendtag(self, tag, attrs):
        if tag.lower() in DROP_WITH_CONTENT:
            return  # e.g. <script/> — nothing inside it
        self.handle_starttag(tag, attrs)
        if tag.lower() in self.stack and tag.lower() not in VOID_TAGS:
            self.handle_endtag(tag)

    def handle_endtag(self, tag):
        tag = tag.lower()
        if self.skip_depth:
            if tag in DROP_WITH_CONTENT and tag not in NO_END_TAG:
                self.skip_depth -= 1
            return
        if tag not in self.stack:
            return
        # close everything opened after it, then the tag itself
        while self.stack:
            open_tag = self.stack.pop()
            self.out.append(f"</{open_tag}>")
            if open_tag == tag:
                break

    # -- text --
    def handle_data(self, data):
        if not self.skip_depth:
            self.out.append(html.escape(data, quote=False))

    def handle_comment(self, data):
        pass  # comments (and IE conditional comments) are dropped

    def result(self):
        while self.stack:
            self.out.append(f"</{self.stack.pop()}>")
        return "".join(self.out)


def clean_email_html(raw_html, inline_images=None):
    """Return safe HTML (or "" if nothing is left).
    inline_images: {content_id: "data:image/png;base64,..."} — replaces cid: links
    so logos in the header/footer show in their place."""
    if not raw_html:
        return ""
    raw_html = str(raw_html)[:2_000_000]
    for cid, data_uri in (inline_images or {}).items():
        raw_html = re.sub(r"cid:<?" + re.escape(cid) + r">?", data_uri, raw_html, flags=re.I)
    cleaner = _Cleaner()
    try:
        cleaner.feed(raw_html)
        cleaner.close()
    except Exception:
        return ""
    safe = cleaner.result().strip()
    if len(safe) > MAX_HTML:
        return ""  # too big to show safely — the plain text is used instead
    return safe
