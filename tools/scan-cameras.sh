#!/bin/bash
# Panasonic PTZ camera scanner (read-only: it only asks cameras for info, never moves them).
#
# Usage:
#   bash scan-cameras.sh                 # scans your Mac's own network (x.x.x.1-254)
#   bash scan-cameras.sh 192.168.10      # scans 192.168.10.1-254 (your camera VLAN)
#   bash scan-cameras.sh 192.168.10 admin password   # if the cameras ask for a login
#
# Results are printed and also saved to cameras.csv next to where you run it.

PREFIX="$1"
USER_NAME="$2"
PASS="$3"

if [ -z "$PREFIX" ]; then
  MYIP=""
  for IF in en0 en1 en2 en3 en4 en5 en6 en7 en8; do
    MYIP=$(ipconfig getifaddr "$IF" 2>/dev/null) && [ -n "$MYIP" ] && break
  done
  [ -z "$MYIP" ] && MYIP=$(hostname -I 2>/dev/null | awk '{print $1}')
  if [ -z "$MYIP" ]; then
    echo "Couldn't find this computer's IP. Run it like: bash scan-cameras.sh 192.168.10"
    exit 1
  fi
  PREFIX=$(echo "$MYIP" | cut -d. -f1-3)
  echo "This Mac is $MYIP, so scanning $PREFIX.1-254"
else
  echo "Scanning $PREFIX.1-254"
fi
echo "This takes about 30 seconds..."
echo

AUTH=""
[ -n "$USER_NAME" ] && AUTH="--digest -u $USER_NAME:$PASS"
export AUTH

probe() {
  IP="$1"
  # Panasonic camera command: QID = ask for model name. Reply looks like "OID:AW-UE150"
  R=$(curl -s -m 2 $AUTH "http://$IP/cgi-bin/aw_cam?cmd=QID&res=1" 2>/dev/null)
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -m 2 $AUTH "http://$IP/cgi-bin/aw_cam?cmd=QID&res=1" 2>/dev/null)
  case "$R" in
    OID:*) ;;
    *)
      if [ "$CODE" = "401" ]; then
        echo "$IP,LOGIN NEEDED,,,,,,"
      fi
      return ;;
  esac
  MODEL=${R#OID:}
  MODEL=$(echo "$MODEL" | tr -d '\r\n')
  NAME=$(curl -s -m 2 $AUTH "http://$IP/cgi-bin/aw_cam?cmd=QTN&res=1" | tr -d '\r\n'); NAME=${NAME#OTN:}
  FW=$(curl -s -m 2 $AUTH "http://$IP/cgi-bin/aw_cam?cmd=QSV&res=1" | tr -d '\r\n'); FW=${FW#OSV:}
  # Power state: p1 = on, p0 = standby
  PWR=$(curl -s -m 2 $AUTH "http://$IP/cgi-bin/aw_ptz?cmd=%23O&res=1" | tr -d '\r\n')
  case "$PWR" in p1) PWR="on";; p0) PWR="standby";; p3) PWR="powering on";; *) PWR="unknown ($PWR)";; esac
  # Pan/tilt position query: proves PTZ control works
  PT=$(curl -s -m 2 $AUTH "http://$IP/cgi-bin/aw_ptz?cmd=%23APC&res=1" | tr -d '\r\n')
  case "$PT" in aPC*) CTRL="yes";; *) CTRL="no ($PT)";; esac
  # RTSP video port
  if nc -z -w 2 "$IP" 554 >/dev/null 2>&1; then RTSP="yes"; else RTSP="no"; fi
  # NDI|HX uses port 5960+ when enabled
  if nc -z -w 2 "$IP" 5961 >/dev/null 2>&1 || nc -z -w 2 "$IP" 5960 >/dev/null 2>&1; then NDI="likely"; else NDI="no"; fi
  echo "$IP,$MODEL,$NAME,$FW,$PWR,$CTRL,$RTSP,$NDI"
}
export -f probe

OUT="cameras.csv"
echo "IP,Model,Name,Firmware,Power,PTZ control,RTSP video,NDI" > "$OUT"
seq 1 254 | sed "s/^/$PREFIX./" | xargs -P 64 -I{} bash -c 'probe {}' | sort -t. -k4 -n >> "$OUT"

COUNT=$(($(wc -l < "$OUT") - 1))
if [ "$COUNT" -eq 0 ]; then
  echo "No Panasonic cameras found on $PREFIX.x"
  echo "If the cameras are on a different network, run: bash scan-cameras.sh <first three numbers of a camera IP>"
  exit 0
fi

column -s, -t < "$OUT"
echo
echo "Found $COUNT camera(s). Saved to $(pwd)/$OUT"
echo "Please send cameras.csv (or paste the table above) back to Claude."
