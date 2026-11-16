#!/usr/bin/env bash
# Stands in for `claude -p --input-format stream-json`: echoes each user message back as a result.
exit_after=0; slow=0
for a in "$@"; do [ "$a" = "exit-after-1" ] && exit_after=1; [ "$a" = "slow" ] && slow=1; done
while IFS= read -r line; do
  content=$(printf '%s' "$line" | sed -E 's/.*"content":"(.*)"\}\}$/\1/')
  [ "$slow" = 1 ] && sleep 0.3
  printf '{"type":"system","subtype":"init"}\n'
  printf '{"type":"result","result":"ECHO:%s","is_error":false}\n' "$content"
  [ "$exit_after" = 1 ] && exit 0
done
