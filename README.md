# Nikko v5.3 — Automated Phishing Tool

**Author:** HEXDECODER (DEM)  
**For authorized penetration testing only**

## Features
- 35+ phishing page templates (Facebook, Instagram, Google, Netflix, etc.)
- Real IP detection via X-Forwarded-For, X-Real-IP, CF-Connecting-IP headers
- IP geolocation (country, city, ISP)
- Browser fingerprinting (screen, timezone, language, platform, CPU, RAM)
- Real-time credential monitoring
- Redirects victims to the real website after capture
- Multiple tunnel options: Ngrok, Cloudflared, LocalXpose, Serveo
- URL masking support

## Installation

```bash
git clone https://github.com/YOUR_USERNAME/nikko-phishing-tool.git
cd nikko-phishing-tool
chmod +x nikko.sh
./nikko.sh
