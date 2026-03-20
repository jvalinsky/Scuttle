#!/bin/zsh
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/../.." && pwd)
OUT_DIR=${1:-"$ROOT_DIR/Tests/Fixtures/Git"}
TMP_DIR=$(mktemp -d /tmp/scuttle-git-fixtures.XXXXXX)
REPO_DIR="$TMP_DIR/repo"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/delta-ref.pack \
      "$OUT_DIR"/delta-ref.idx \
      "$OUT_DIR"/delta-ofs.pack \
      "$OUT_DIR"/delta-ofs.idx \
      "$OUT_DIR"/manifest.json

git init -q -b main "$REPO_DIR"
cd "$REPO_DIR"
git config user.name Fixture
git config user.email fixture@example.com

perl -e 'print "alpha line $_ same same same same same same same same same same\n" for 1..400' > file.txt
GIT_AUTHOR_DATE='2020-01-01T00:00:00Z' \
GIT_COMMITTER_DATE='2020-01-01T00:00:00Z' \
git add file.txt
GIT_AUTHOR_DATE='2020-01-01T00:00:00Z' \
GIT_COMMITTER_DATE='2020-01-01T00:00:00Z' \
git commit -q -m initial

cp file.txt file2.txt
perl -0pi -e 's/alpha line 200/alpha line 200 updated/' file.txt
perl -0pi -e 's/alpha line 300/alpha line 300 updated/' file2.txt
GIT_AUTHOR_DATE='2020-01-02T00:00:00Z' \
GIT_COMMITTER_DATE='2020-01-02T00:00:00Z' \
git add file.txt file2.txt
GIT_AUTHOR_DATE='2020-01-02T00:00:00Z' \
GIT_COMMITTER_DATE='2020-01-02T00:00:00Z' \
git commit -q -m second

HEAD_COMMIT=$(git rev-parse HEAD)
PREV_COMMIT=$(git rev-parse HEAD~1)
HEAD_TREE=$(git rev-parse HEAD^{tree})
PREV_TREE=$(git rev-parse HEAD~1^{tree})
BASE_BLOB=$(git rev-parse HEAD~1:file.txt)
FILE1_BLOB=$(git rev-parse HEAD:file.txt)
FILE2_BLOB=$(git rev-parse HEAD:file2.txt)

git rev-list --objects --all | git pack-objects --window=50 --depth=50 --stdout > "$OUT_DIR/delta-ref.pack"
git index-pack -o "$OUT_DIR/delta-ref.idx" "$OUT_DIR/delta-ref.pack" >/dev/null

git rev-list --objects --all | git pack-objects --window=50 --depth=50 --delta-base-offset --stdout > "$OUT_DIR/delta-ofs.pack"
git index-pack -o "$OUT_DIR/delta-ofs.idx" "$OUT_DIR/delta-ofs.pack" >/dev/null

rm -f "$OUT_DIR"/delta-ref.rev "$OUT_DIR"/delta-ofs.rev

REF_VERIFY=$(git verify-pack -v "$OUT_DIR/delta-ref.idx" 2>&1 || true)
if [[ "$REF_VERIFY" != *"chain length = 1"* ]]; then
  echo "delta-ref fixture did not contain delta objects" >&2
  exit 1
fi

OFS_VERIFY=$(git verify-pack -v "$OUT_DIR/delta-ofs.idx" 2>&1 || true)
if [[ "$OFS_VERIFY" != *"chain length = 1"* ]]; then
  echo "delta-ofs fixture did not contain delta objects" >&2
  exit 1
fi

cat > "$OUT_DIR/manifest.json" <<EOF
{
  "commit_head": "$HEAD_COMMIT",
  "commit_previous": "$PREV_COMMIT",
  "tree_head": "$HEAD_TREE",
  "tree_previous": "$PREV_TREE",
  "blob_base": "$BASE_BLOB",
  "blob_file1_updated": "$FILE1_BLOB",
  "blob_file2_updated": "$FILE2_BLOB"
}
EOF

printf 'Wrote fixtures to %s\n' "$OUT_DIR"
