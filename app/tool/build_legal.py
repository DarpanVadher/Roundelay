"""Generates the legal pages: site/legal/*.html and app/lib/legal/legal_data.dart from one source.
Run: python app/tool/build_legal.py"""
import html, os
from html.parser import HTMLParser

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "site", "legal")
BASE = "https://darpanvadher.github.io/Roundelay/"
REPO = "https://github.com/DarpanVadher/Roundelay"
UPDATED = "12 November 2026"
os.makedirs(OUT, exist_ok=True)

SEC = f"{REPO}/security/advisories/new"
ISSUES = f"{REPO}/issues"

PAGES = [
 ("privacy-policy", "Privacy Policy", "What Roundelay does and does not do with information.",
  "Roundelay has no accounts, no analytics and no servers of its own. Audio and pairing traffic stay on your local network.",
  [("What we collect",
    "<p>Nothing. The app and this website do not collect, receive or store personal data on any server run by the Roundelay authors. We do not run servers for the app, and there is no sign-up, advertising, tracking or telemetry.</p>"),
   ("What stays on your devices",
    "<ul><li><strong>Audio</strong> is captured on the host, encrypted, and sent directly to the guests you approve over your Wi-Fi, hotspot or LAN (UDP for audio, TCP for pairing). It is not sent to the internet and is not recorded or saved by the app.</li>"
    "<li><strong>Pairing details</strong>: a guest's device name and local network address are shown to the host so the host can approve or deny the join. They are held in memory while connected and are not persisted.</li>"
    "<li><strong>The host's identity key</strong> is saved as a file in the host's own data folder so guests can recognise it. On Windows this is <code>%APPDATA%\\MultiPhonePlayer</code>. It never leaves the device.</li>"
    "<li><strong>Hotspot Wi-Fi details</strong> (optional): if a host switches on <em>Include hotspot Wi-Fi in the QR</em>, the name and password they typed are saved on that device only, and are placed inside the pairing QR code and link so guests can join the hotspot and pair in one scan. Anyone who can see that QR can read the password. A hotspot the app creates itself is not remembered.</li>"
    "<li><strong>Diagnostics</strong>: the app only writes a local trace when someone starts it with the trace option on, and that trace stays on that device.</li></ul>"),
   ("Android permissions",
    "<ul><li><strong>Record audio and media projection</strong>: so a host can capture what other apps play. Android asks you each time.</li>"
    "<li><strong>Camera</strong>: so a guest can scan the host's QR code. Frames are decoded on the device, using Google ML Kit's on-device scanner, and are not stored or sent anywhere by Roundelay. You can skip the camera and paste the pairing link instead.</li>"
    "<li><strong>Nearby devices (Android 13 and newer) or location (older)</strong>: only if you tap <em>Create a hotspot for me</em>; Android requires it to start a hotspot. The app does not read your location.</li>"
    "<li><strong>Change Wi-Fi / network state</strong>: so a guest can join the hotspot named in a scanned QR. Android asks you to confirm each time.</li>"
    "<li><strong>Network, Wi-Fi state, wake lock, notifications, foreground service</strong>: to stay connected and keep playing with the screen off.</li></ul>"),
   ("This website",
    "<p>The site is static pages hosted on GitHub Pages. It sets no cookies and uses no analytics. Fonts are served from the site itself. The download section loads a small <code>release.json</code> from the same site and, if that fails, asks the GitHub API for the latest release; GitHub can therefore see your IP address and browser details, as it does for any GitHub page. See <a href=\"third-party-disclosure.html\">Third-party disclosure</a>.</p>"),
   ("Children",
    "<p>Roundelay is not directed at children and does not knowingly collect anything from anyone, including children.</p>"),
   ("Changes and questions",
    f"<p>If this policy changes, the date above changes and the previous text stays in the <a href=\"{REPO}/commits/main/site/legal\">public history</a>. Questions: open an <a href=\"{ISSUES}\">issue</a> (please do not post personal data in it).</p>")]),

 ("terms-and-conditions", "Terms & Conditions", "The rules for using Roundelay and this website.",
  "Roundelay is free, open-source, early-stage software provided as is.",
  [("Using Roundelay",
    "<p>You may install and use Roundelay on devices you own or are allowed to use, on networks you are allowed to use. The software is licensed under the <a href=\"https://www.apache.org/licenses/LICENSE-2.0\">Apache License 2.0</a>, which also governs copying and modifying the code.</p>"),
   ("Early-stage software, no warranty",
    "<p>Roundelay is early and experimental. Its pairing and encryption design has not been independently audited. It is provided <strong>&ldquo;as is&rdquo;, without warranties of any kind</strong>, as set out in the Apache License. Do not rely on it for anything where a failure, dropout or sync error would cause harm.</p>"),
   ("What you share",
    "<p>The host decides what audio is shared and who may listen. You are responsible for having the right to play and share that audio, and for following the terms of any music, video or streaming service you capture. Some apps block audio capture, and Roundelay cannot share those.</p>"),
   ("Acceptable use",
    "<ul><li>Approve only devices you recognise; the host sees every join request.</li><li>Do not use Roundelay to listen in on people, bypass access controls, or disrupt a network.</li><li>Do not attempt to attack or reverse-engineer other people's devices with it.</li></ul>"),
   ("Liability",
    "<p>To the extent the law allows, the Roundelay authors are not liable for loss or damage arising from use of the software or this website. Nothing here limits liability that cannot be limited by law, such as for death or personal injury caused by negligence, or for fraud.</p>"),
   ("Changes and contact",
    f"<p>We may update these terms; the date above shows the latest version and <a href=\"{REPO}/commits/main/site/legal\">history is public</a>. Contact: <a href=\"{ISSUES}\">open an issue</a>. Security problems go through the <a href=\"{SEC}\">private advisory form</a>.</p>")]),

 ("gdpr-compliance", "GDPR Compliance", "How Roundelay relates to the EU and UK GDPR.",
  "The project is built so that it does not hold personal data. This page explains what that means and what rights you still have.",
  [("Our role",
    "<p>The Roundelay authors do not operate a service that receives personal data from the app. For the app, there is no controller-run processing to describe: everything happens between devices you control. For the website, GitHub hosts the pages and is responsible for its own server logs under its own privacy statement.</p>"),
   ("Data minimisation by design",
    "<ul><li>No accounts, no email addresses, no analytics, no advertising identifiers.</li><li>Pairing uses a single-use token and a QR fingerprint; paired devices are not saved.</li><li>The only file written is the host's own identity key, on that host.</li></ul>"),
   ("Your rights",
    "<p>You have the right to access, correct, erase, restrict and port your data, to object to processing, and to complain to your supervisory authority. Because the authors hold no personal data about app users, there is normally nothing to access or erase. See <a href=\"data-deletion.html\">Data Deletion</a> for removing the files that exist on your own devices. If you think we do hold something about you, open an <a href=\"" + ISSUES + "\">issue</a> without personal details and we will arrange a private channel.</p>"),
   ("International transfers",
    "<p>The app sends nothing to us. Visiting the website involves GitHub, which may process data outside your country under its own safeguards.</p>"),
   ("Organisations deploying Roundelay",
    "<p>If your organisation runs Roundelay for staff or customers, your organisation decides the purposes and is the controller for anything it chooses to log or retain. The software does not do that on its own.</p>")]),

 ("cookie-consent", "Cookie Consent", "Cookies and similar storage on this site and in the app.",
  "This website and the Roundelay app set no cookies and use no local storage for tracking, so there is no consent banner.",
  [("Website",
    "<p>The pages store nothing in your browser: no cookies, no local storage, no session storage, no fingerprinting and no third-party scripts. A consent banner would have nothing to ask about.</p>"),
   ("App",
    "<p>The app does not use cookies. Its only stored file is the host's identity key (see the <a href=\"privacy-policy.html\">Privacy Policy</a>).</p>"),
   ("GitHub",
    "<p>If you follow a link to GitHub (for downloads or the source), GitHub's own cookie notice applies on its pages.</p>"),
   ("If this changes",
    "<p>If we ever add anything that needs consent, we will ask first, before it runs, and update this page.</p>")]),

 ("legal-basis", "Legal Basis", "Why any information is handled at all.",
  "Almost nothing is processed by the authors. Where information is handled, this is the reason.",
  [("Pairing between your devices",
    "<p>When a guest joins a host, the host sees the guest's device name and local address so it can approve or deny. This happens at the user's own request (a person scans the code or pastes the link), and is needed to perform what the user asked for: sharing audio between their devices. It is neither stored nor sent to the authors.</p>"),
   ("Website visits",
    "<p>Serving a web page involves your IP address reaching GitHub's servers. That processing is done by GitHub for delivering and securing its service. The authors receive no visitor data and use no analytics.</p>"),
   ("Security reports",
    "<p>If you report a vulnerability, we use what you send to investigate and fix it, and to credit you if you ask. We rely on our legitimate interest in keeping the software safe, and on your choice to contact us.</p>"),
   ("Consent",
    "<p>We do not rely on consent for anything the app does, because the app collects no personal data. Camera and audio capture are controlled by operating-system permissions that you grant or refuse.</p>")]),

 ("marketing-consent", "Marketing Consent", "Whether we contact you.",
  "We do not send marketing, so there is nothing to opt in to or out of.",
  [("No mailing list",
    "<p>Roundelay has no newsletter, no email list, no push marketing and no in-app promotions. We do not hold your contact details.</p>"),
   ("No advertising",
    "<p>The app and website contain no ads and do not share information with advertisers.</p>"),
   ("Release news",
    f"<p>If you want to hear about new versions, you can watch the project's <a href=\"{REPO}/releases\">releases on GitHub</a>. That is your GitHub account's setting, and the authors do not receive your address from it.</p>"),
   ("If this changes",
    "<p>Should we ever start sending anything promotional, it will be opt-in with a clear way to withdraw, and this page will be updated first.</p>")]),

 ("data-deletion", "Data Deletion", "How to remove everything Roundelay has put on your devices.",
  "We hold no account data to delete. The files on your own devices are removed by uninstalling and deleting one folder.",
  [("Nothing on our side",
    "<p>There is no account or server-side profile, so there is nothing to ask us to delete.</p>"),
   ("On your devices",
    "<ol><li><strong>Windows:</strong> uninstall Roundelay from Settings, then delete <code>%APPDATA%\\MultiPhonePlayer</code> (this holds the host identity key; guests will then no longer recognise this host and must pair again).</li>"
    "<li><strong>Android:</strong> uninstall the app, or use Settings &rsaquo; Apps &rsaquo; Roundelay &rsaquo; Storage &rsaquo; Clear data.</li>"
    "<li><strong>Linux:</strong> delete <code>~/.config/multiphone-player</code> (or <code>$XDG_CONFIG_HOME/multiphone-player</code>).</li>"
    "<li><strong>macOS:</strong> the same folder under your home directory (<code>~/.config/multiphone-player</code>).</li></ol>"),
   ("Saved Wi-Fi details",
    "<p>If you saved a hotspot name and password on a host, clear both fields in the host screen (or switch the option off and delete the data folder above). Guests never save them.</p>"),
   ("Revoking access",
    "<p>Guests are not remembered after they leave. To remove a connected device right away, use <em>Disconnect</em> beside it on the host screen.</p>"),
   ("Website and GitHub",
    "<p>To remove anything GitHub holds about you (for example an issue you opened), use your GitHub account settings or ask GitHub; the Roundelay authors cannot delete data on GitHub's behalf, but can delete issues you ask us to when it is within our power.</p>")]),

 ("data-retention", "Data Retention", "How long anything is kept.",
  "The authors retain no user data. On your devices, each item lives only as long as shown here.",
  [("Retention table",
    "<table><thead><tr><th>Item</th><th>Where</th><th>Kept until</th></tr></thead><tbody>"
    "<tr><td>Audio stream</td><td>In memory on host and guests</td><td>Not kept; played and discarded</td></tr>"
    "<tr><td>Guest name and address</td><td>In memory on the host</td><td>The guest disconnects or the app closes</td></tr>"
    "<tr><td>Single-use join token</td><td>QR code / link</td><td>Used once; a new one is made each time</td></tr>"
    "<tr><td>Host identity key</td><td>File in the host's data folder</td><td>You delete it (see <a href=\"data-deletion.html\">Data Deletion</a>)</td></tr>"
    "<tr><td>Hotspot name and password you typed</td><td>File in the app's data folder, on the host</td><td>You switch it off and delete the data folder, or uninstall</td></tr>"
    "<tr><td>Hotspot made by the app</td><td>Android, while the host screen is open</td><td>You leave the host screen or tap <em>Stop app hotspot</em></td></tr>"
    "<tr><td>Diagnostic trace</td><td>Local, only if switched on</td><td>You delete it</td></tr>"
    "<tr><td>Web server logs</td><td>GitHub</td><td>Per GitHub's own policy</td></tr>"
    "</tbody></table>"),
   ("Security reports",
    "<p>Vulnerability reports and any contact details in them are kept for as long as needed to fix the issue and publish an advisory, then deleted from our side on request.</p>")]),

 ("data-processing-agreements", "Data Processing Agreements", "Whether a DPA is needed.",
  "No, because the authors do not process personal data for you. Here is the reasoning and what to do if you disagree.",
  [("Why none is needed",
    "<p>A data processing agreement is required when one party processes personal data on behalf of another. Roundelay is software that runs on your own devices; the authors never receive or handle your data, so there is no processing on your behalf to govern.</p>"),
   ("Sub-processors",
    "<p>We use none. The only third party involved is GitHub, which hosts this website and the downloads under its own terms and data-protection addendum.</p>"),
   ("Organisations",
    "<p>If your organisation's compliance team needs a statement for its records, this page and the <a href=\"privacy-policy.html\">Privacy Policy</a> describe the data flows. If you need more, open an <a href=\"" + ISSUES + "\">issue</a> and tell us what is missing. You may also review the source code, as it is public.</p>")]),

 ("third-party-disclosure", "Third-Party Disclosure", "Who else is involved, and what they can see.",
  "We do not sell or share your information. These are the outside parties that touch the project.",
  [("GitHub",
    f"<p>Hosts the <a href=\"{REPO}\">source code</a>, the <a href=\"{REPO}/releases\">release downloads</a> and this website (GitHub Pages). When you visit or download, GitHub sees your IP address and request details under <a href=\"https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement\">its own privacy statement</a>.</p>"),
   ("Google ML Kit (Android only)",
    "<p>The Android QR scanner uses Google ML Kit's barcode scanning. Per the project's <a href=\"" + REPO + "/blob/main/THIRD_PARTY_NOTICES.md\">third-party notices</a>, it is proprietary and governed by Google's terms. Scanning is intended to run on the device; Roundelay does not send camera images to us or any other server. If you prefer, skip scanning and paste the link.</p>"),
   ("Operating systems",
    "<p>Windows, Android and others handle audio capture, camera and network permissions. What they collect is covered by your operating system vendor's policies, not ours.</p>"),
   ("Open-source components",
    "<p>The app is built from open-source libraries (see <a href=\"open-source-licences.html\">Open-Source Licences</a>). They run inside the app and do not send data anywhere on their own.</p>"),
   ("Disclosure to authorities",
    "<p>We hold no user data to disclose. If we were legally required to hand over something, we would give only what we have, such as the text of a vulnerability report.</p>")]),

 ("data-security", "Data Security", "How Roundelay protects audio and pairing.",
  "Encrypted per-guest keys, a pinned host fingerprint and host approval for every device. It has not yet been independently reviewed.",
  [("What protects you",
    "<ul><li><strong>Pairing</strong> uses a Noise XX handshake.</li><li><strong>Audio and control packets</strong> are encrypted with ChaCha20-Poly1305, with a separate key for each guest.</li><li><strong>Fingerprint pinning</strong>: the QR code carries a fingerprint of the host's identity, so a guest refuses to talk to an impostor and never sends its one-time token to the wrong device.</li><li><strong>Host approval</strong>: every device must be approved on the host before it hears anything.</li><li><strong>Single-use tokens</strong>: each join uses a fresh token.</li><li><strong>Local network only</strong>: no relay servers.</li><li><strong>Wi-Fi in the QR is opt-in</strong>: it is off by default, and the host screen warns that anyone who sees the QR can read the Wi-Fi password in it. Use a hotspot password you do not reuse elsewhere.</li></ul>"),
   ("Known limitations",
    "<ul><li>The design has <strong>not been independently audited</strong>.</li><li>The host's identity key is stored as a plain file in its data folder.</li><li>Nothing protects against someone who can already run code on the host or guest device.</li><li>Anyone on your network can see that Roundelay traffic exists, though not its content.</li></ul>"),
   ("What you can do",
    "<p>Use a network you trust, approve only devices you recognise, keep the app and your operating system up to date, and report anything suspicious through the <a href=\"" + SEC + "\">private advisory form</a>.</p>")]),

 ("data-breach-procedure", "Data Breach Procedure", "What we do if something goes wrong.",
  "Since the project holds no user data, a breach would mean a vulnerability in the software or its release pipeline. This is how we handle one.",
  [("Reporting",
    f"<p>Report privately using the <a href=\"{SEC}\">GitHub security advisory form</a>, not a public issue. Include what you found, how to reproduce it and what an attacker could do. We aim to acknowledge within a few days.</p>"),
   ("What we do",
    "<ol><li>Confirm and assess the problem, and what it could expose.</li><li>Fix it on the <code>main</code> branch (there are no supported release branches yet) and ship a new release.</li><li>Publish a GitHub security advisory describing the issue, who is affected and how to update, crediting the reporter if they wish.</li><li>If a release file or this website were compromised, withdraw the affected downloads and say so in the release notes and on this site.</li></ol>"),
   ("Notifying you",
    "<p>We have no list of users to contact, so notices are public: the advisory, release notes and this website. If personal data of yours were ever involved, we would tell the people affected and any required authority within the legal deadlines, which is 72 hours to a supervisory authority under the GDPR where it applies.</p>")]),

 ("intellectual-property", "Intellectual Property", "Who owns what.",
  "The code is open source; the name, the content you play, and third-party components keep their own owners.",
  [("The code",
    "<p>Copyright 2026 The Roundelay Authors. Licensed under the <a href=\"https://www.apache.org/licenses/LICENSE-2.0\">Apache License 2.0</a> (see the <a href=\"" + REPO + "/blob/main/LICENSE\">LICENSE</a> and <a href=\"" + REPO + "/blob/main/NOTICE\">NOTICE</a> files). You may use, modify and redistribute it under that licence.</p>"),
   ("Name and logo",
    "<p>The licence covers the code. As Apache License section 6 says, it does not grant permission to use the Roundelay name or logo, except to describe where the software came from. Please do not present a modified build as the official one.</p>"),
   ("Content you play",
    "<p>Audio played through Roundelay belongs to its owners. Roundelay does not copy, host or distribute any of it; you are responsible for having the right to share what you play.</p>"),
   ("Contributions",
    f"<p>Contributions are accepted under the same Apache 2.0 licence, as described in <a href=\"{REPO}/blob/main/CONTRIBUTING.md\">CONTRIBUTING.md</a>.</p>"),
   ("Reporting infringement",
    f"<p>If you believe something in this project infringes your rights, <a href=\"{ISSUES}\">open an issue</a> or contact us through GitHub with enough detail to identify it.</p>")]),

 ("open-source-licences", "Open-Source Licences", "The licences Roundelay is built on.",
  "Roundelay is Apache-2.0. It includes open-source components whose licences require the notices below.",
  [("Roundelay",
    "<p>Apache License 2.0. Full text: <a href=\"" + REPO + "/blob/main/LICENSE\">LICENSE</a>.</p>"),
   ("Main components",
    "<table><thead><tr><th>Component</th><th>Used for</th><th>Licence</th></tr></thead><tbody>"
    "<tr><td>Opus (libopus)</td><td>Audio codec</td><td>BSD 3-Clause</td></tr>"
    "<tr><td>cpal, Oboe</td><td>Audio input and output</td><td>Apache-2.0</td></tr>"
    "<tr><td>snow</td><td>Noise handshake</td><td>Apache-2.0 or MIT</td></tr>"
    "<tr><td>chacha20poly1305, sha2, rand</td><td>Encryption, hashing</td><td>MIT or Apache-2.0</td></tr>"
    "<tr><td>Flutter, qr_flutter, mobile_scanner, ffi</td><td>App UI, QR, camera, engine bridge</td><td>BSD 3-Clause</td></tr>"
    "<tr><td>cupertino_icons</td><td>Icons</td><td>MIT</td></tr>"
    "<tr><td>Google ML Kit barcode scanning</td><td>Android QR scanning</td><td>Proprietary (Google terms)</td></tr>"
    "<tr><td>Bricolage Grotesque, Figtree</td><td>Website fonts</td><td>SIL Open Font License 1.1</td></tr>"
    "</tbody></table>"),
   ("Full notices",
    "<p>The complete notices, including the BSD text for Opus, are in <a href=\"" + REPO + "/blob/main/THIRD_PARTY_NOTICES.md\">THIRD_PARTY_NOTICES.md</a>. That file covers the components that matter most for distribution and is not a full list of every transitive dependency.</p>")]),

 ("payments-and-subscriptions", "Payments & Subscriptions", "What Roundelay costs.",
  "Nothing. Roundelay is free, with no payments, subscriptions, in-app purchases or ads.",
  [("Free to use",
    "<p>The app and its downloads are free. There is no paid tier, trial, subscription or in-app purchase, and we never ask for a payment card.</p>"),
   ("No payment data",
    "<p>Because nothing is sold, the project never handles payment details. Be careful of any site or app that charges for &ldquo;Roundelay&rdquo;: it is not from us. Official downloads come only from the <a href=\"" + REPO + "/releases\">GitHub releases page</a> and this website.</p>"),
   ("Donations",
    "<p>There is currently no donation or sponsorship option. If one is added, it will be handled by a third-party platform under that platform's terms, and this page will say so.</p>"),
   ("If this changes",
    "<p>Should paid features ever be introduced, we will publish pricing, renewal, cancellation and refund terms here before they take effect.</p>")]),
]

CSS_LINK = '<link rel="stylesheet" href="../style.css">\n<link rel="stylesheet" href="legal.css">'
MARK = '<svg class="mark" viewBox="0 0 32 32" aria-hidden="true"><circle cx="16" cy="16" r="14" fill="none" stroke="currentColor" stroke-width="2.5"/><circle cx="16" cy="16" r="8" fill="none" stroke="currentColor" stroke-width="2.5"/><circle cx="16" cy="16" r="2.6" fill="currentColor"/></svg>'
FOOT = f'''<footer class="foot">
  <div class="wrap foot-row">
    <p>Roundelay is open source under the <a href="https://www.apache.org/licenses/LICENSE-2.0">Apache License 2.0</a>.</p>
    <p><a href="../">Home</a> · <a href="./">All legal pages</a> · <a href="{REPO}">Source</a> · <a href="{ISSUES}">Report an issue</a></p>
  </div>
</footer>'''

def shell(title, desc, slug, eyebrow, h1, lede, body):
    t = html.escape(title)
    return f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{t} · Roundelay</title>
<meta name="description" content="{html.escape(desc)}">
<meta name="theme-color" content="#2433ff">
<link rel="canonical" href="{BASE}legal/{slug}">
<link rel="icon" href="../favicon.svg" type="image/svg+xml">
{CSS_LINK}
</head>
<body>
<a class="skip" href="#main">Skip to content</a>
<header class="legal-hero">
  <div class="top">
    <a class="brand" href="../" aria-label="Roundelay home">{MARK}<span>Roundelay</span></a>
    <nav aria-label="Main"><a href="./">Legal</a><a href="{REPO}">GitHub</a><a class="nav-cta" href="../#download">Download</a></nav>
  </div>
  <div class="wrap legal-title">
    <p class="eyebrow">{eyebrow}</p>
    <h1>{html.escape(h1)}</h1>
    <p class="lede">{lede}</p>
  </div>
</header>
<main id="main" class="wrap legal">
{body}
</main>
{FOOT}
</body>
</html>
'''

n = len(PAGES)
for i, (slug, title, desc, lede, secs) in enumerate(PAGES):
    body = f'<article>\n<p class="updated">Last updated {UPDATED}</p>\n'
    for h, content in secs:
        body += f"<section>\n<h2>{h}</h2>\n{content}\n</section>\n"
    body += "</article>\n<nav class=\"pager\" aria-label=\"Legal pages\">"
    if i > 0:
        p = PAGES[i - 1]
        body += f'<a rel="prev" href="{p[0]}.html"><span>Previous</span>{html.escape(p[1])}</a>'
    else:
        body += "<span></span>"
    if i < n - 1:
        q = PAGES[i + 1]
        body += f'<a rel="next" href="{q[0]}.html"><span>Next</span>{html.escape(q[1])}</a>'
    body += "</nav>"
    page = shell(title, desc, slug + ".html", f"Legal · {i+1:02d} of {n}", title, lede, body)
    open(os.path.join(OUT, slug + ".html"), "w", encoding="utf-8", newline="\n").write(page)

# hub
cards = ""
for i, (slug, title, desc, lede, secs) in enumerate(PAGES):
    cards += f'<li><a href="{slug}.html"><span class="num">{i+1:02d}</span><span class="t">{html.escape(title)}</span><span class="d">{html.escape(desc)}</span></a></li>\n'
hub_body = f'''<article>
<p class="updated">Last updated {UPDATED}</p>
<p>Roundelay shares audio between your own devices on your own network, with no accounts and no servers of ours, so most of these pages are short and say plainly what we do not do. They describe how the project works today.</p>
<p class="note"><strong>Plain-language summaries, not legal advice.</strong> Roundelay is an early-stage open-source project. If you rely on it for compliance, check these pages against your own situation.</p>
<ol class="cards">
{cards}</ol>
</article>'''
hub = shell("Legal", "Privacy, terms, data protection and licences for Roundelay.", "", "Legal", "Legal & privacy",
            "Fifteen short pages on privacy, terms, data and licences.", hub_body)
open(os.path.join(OUT, "index.html"), "w", encoding="utf-8", newline="\n").write(hub)
print("pages", n + 1)


# ---- Dart data for the in-app screens ----
class Blocks(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.blocks, self.buf = [], ""
        self.items, self.rows, self.row = None, None, None

    def text(self):
        return " ".join(self.buf.split())

    def handle_starttag(self, tag, attrs):
        if tag in ("ul", "ol"):
            self.items = []
        elif tag == "table":
            self.rows = []
        elif tag == "tr":
            self.row = []
        elif tag == "strong":
            self.buf += "**"
        elif tag == "code":
            self.buf += "`"
        if tag in ("p", "li", "td", "th"):
            self.buf = ""

    def handle_endtag(self, tag):
        if tag == "strong":
            self.buf += "**"
        elif tag == "code":
            self.buf += "`"
        elif tag == "p":
            self.blocks.append(("p", [self.text()])); self.buf = ""
        elif tag == "li":
            self.items.append(self.text()); self.buf = ""
        elif tag in ("td", "th"):
            self.row.append(self.text()); self.buf = ""
        elif tag == "tr":
            self.rows.append(self.row)
        elif tag in ("ul", "ol"):
            self.blocks.append((tag, self.items)); self.items = None
        elif tag == "table":
            self.blocks.append(("table", self.rows)); self.rows = None

    def handle_data(self, d):
        self.buf += d


def dq(t):
    return "'" + t.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$").replace("\n", " ") + "'"


def blocks_of(content):
    p = Blocks()
    p.feed(content)
    return p.blocks


dart = [
    "// GENERATED by app/tool/build_legal.py from the same source as site/legal. Do not edit by hand.",
    "",
    "enum LegalKind { paragraph, bullets, numbered, table }",
    "",
    "class LegalBlock {",
    "  const LegalBlock(this.kind, this.items, [this.rows = const []]);",
    "  final LegalKind kind;",
    "  final List<String> items;",
    "  final List<List<String>> rows;",
    "}",
    "",
    "class LegalSection {",
    "  const LegalSection(this.title, this.blocks);",
    "  final String title;",
    "  final List<LegalBlock> blocks;",
    "}",
    "",
    "class LegalPage {",
    "  const LegalPage(this.slug, this.title, this.summary, this.lede, this.sections);",
    "  final String slug, title, summary, lede;",
    "  final List<LegalSection> sections;",
    "  String get url => 'https://darpanvadher.github.io/Roundelay/legal/$slug.html';",
    "}",
    "",
    f"const legalUpdated = {dq(UPDATED)};",
    "",
    "const legalPages = <LegalPage>[",
]
kinds = {"p": "paragraph", "ul": "bullets", "ol": "numbered", "table": "table"}
for slug, title, desc, lede, secs in PAGES:
    dart.append(f"  LegalPage({dq(slug)}, {dq(title)}, {dq(desc)}, {dq(lede)}, [")
    for h, content in secs:
        dart.append(f"    LegalSection({dq(h)}, [")
        for k, v in blocks_of(content):
            if k == "table":
                rows = ", ".join("[" + ", ".join(dq(c) for c in r) + "]" for r in v)
                dart.append(f"      LegalBlock(LegalKind.table, [], [{rows}]),")
            else:
                dart.append(f"      LegalBlock(LegalKind.{kinds[k]}, [{', '.join(dq(x) for x in v)}]),")
        dart.append("    ]),")
    dart.append("  ]),")
dart.append("];")
dest = os.path.join(ROOT, "app", "lib", "legal")
os.makedirs(dest, exist_ok=True)
open(os.path.join(dest, "legal_data.dart"), "w", encoding="utf-8", newline="\n").write("\n".join(dart) + "\n")
print("dart written")
