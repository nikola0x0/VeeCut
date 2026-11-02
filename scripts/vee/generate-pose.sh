#!/bin/zsh
# Generates one Vee pose with Muse Image from the shared style, then cuts it out.
# Usage: scripts/vee/generate-pose.sh <name> "<pose description>"  (needs MODEL_API_KEY; writes Images/Vee/<name>.png)
set -euo pipefail
here=${0:A:h}
name=$1; pose=$2
[[ -n ${MODEL_API_KEY:-} ]] || source ~/.zshenv
work=$(mktemp -d); trap 'rm -rf $work' EXIT
prompt="$(cat $here/vee-style.txt) Pose: $pose"
python3 -c 'import json,sys; print(json.dumps({"model":"muse-image-1.0","prompt":sys.argv[1],"n":1,"size":"1024x1024","output_format":"png","reasoning_strength":"high"}))' "$prompt" > $work/req.json
for attempt in 1 2 3; do
  code=$(curl -s -o $work/resp.json -w "%{http_code}" https://api.meta.ai/v1/images/generations \
    -H "Authorization: Bearer $MODEL_API_KEY" -H "Content-Type: application/json" --data @$work/req.json)
  [[ $code == 200 ]] && break
  sleep $attempt
done
[[ $code == 200 ]] || { echo "Muse Image failed ($code): $(head -c 300 $work/resp.json)" >&2; exit 1; }
python3 -c 'import json,base64,sys; open(sys.argv[2],"wb").write(base64.b64decode(json.load(open(sys.argv[1]))["data"][0]["b64_json"]))' $work/resp.json $work/raw.png
out=${VEE_OUT_DIR:-$here/../../Sources/PalmierPro/Resources/Images/Vee}/$name.png
swift $here/cutout.swift $work/raw.png $out
echo "$out"
