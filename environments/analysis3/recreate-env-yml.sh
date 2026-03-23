#!/bin/bash -l
set -e 

(
echo "name: analysis3"
echo "channels:"
echo "  - accessnri"
echo "  - conda-forge"
echo "  - nodefaults"
echo "  - rapidsai"
echo "  - pytorch"
echo "  - nvidia"
echo "dependencies:"

# Conda packages
jq -r '
.[] 
| select(.name | startswith("__") | not)
| select(.name | startswith("_") | not)
| select(.build != null)
| "  - \(.name)=\(.version)=\(.build)"
' solved.json

echo "  - pip"
echo "  - pip:"

# Pip packages
jq -r '
.[] 
| select(.name | startswith("__") | not)
| select(.name | startswith("_") | not)
| select(.build == null)
| "    - \(.name | gsub("_"; "-"))==\(.version)"
' solved.json

) > environment.yml