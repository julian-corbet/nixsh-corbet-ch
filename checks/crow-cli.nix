{ pkgs, crowCli }:

pkgs.runCommand "crow-cli-check" {
  nativeBuildInputs = [ crowCli ];
} ''
  test "$(crow --version)" = "crow version 6.5.0"

  cat > workflow.yaml <<'EOF'
steps:
  - name: smoke
    image: alpine
    commands:
      - echo ok
when:
  - event: push
EOF
  crow --disable-update-check lint --strict workflow.yaml
  touch "$out"
''
