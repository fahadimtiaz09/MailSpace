"""headers.py — security headers added to every response.

They tell the browser to:
  * only ever use HTTPS for domailit.com (HSTS)
  * never run scripts from other websites (Content-Security-Policy)
  * never show DoMailit inside another site's frame (stops "clickjacking")
  * not guess file types, and not leak full page addresses to other sites
  * allow camera/microphone only for DoMailit itself (calls)

Emails are shown in a sandboxed iframe that inherits this policy, so pictures,
styles and fonts from any https site are still allowed (emails need them);
scripts are not.
"""
from flask import request

CSP = "; ".join([
    "default-src 'self'",
    "script-src 'self'",
    "style-src 'self' 'unsafe-inline' https:",
    "img-src 'self' data: blob: https: http:",
    "font-src 'self' data: https:",
    "media-src 'self' blob:",
    "connect-src 'self'",
    "worker-src 'self'",
    "manifest-src 'self'",
    "frame-src 'self'",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
])

HEADERS = {
    "Content-Security-Policy": CSP,
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "strict-origin-when-cross-origin",
    "Permissions-Policy": "camera=(self), microphone=(self), geolocation=(), payment=(), usb=(), interest-cohort=()",
    "Cross-Origin-Opener-Policy": "same-origin",
}

# Two years, all subdomains, ready for the browsers' built-in HTTPS list (hstspreload.org).
HSTS = "max-age=63072000; includeSubDomains; preload"


def add_security_headers(response):
    for name, value in HEADERS.items():
        response.headers.setdefault(name, value)
    if request.is_secure:
        response.headers.setdefault("Strict-Transport-Security", HSTS)
    return response
