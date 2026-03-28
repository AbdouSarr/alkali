# Visual Regression in CI

Use Alkali to detect unintended visual changes in your SwiftUI views as part of your CI pipeline.

## How It Works

1. **Set a baseline**: Render all views at all variants, save the AXIR snapshots
2. **On each PR**: Re-render and diff against the baseline
3. **Report drift**: Any structural changes (modifier values, added/removed nodes, layout shifts) are flagged

This works without pixel comparison — Alkali diffs the AXIR trees semantically, so it tells you *what* changed (e.g., "padding changed from 16 to 24 on ProfileCard") rather than just "pixels differ."

## Setup

### 1. Create a baseline

```bash
alkali preview --all --set-baseline --project-root .
```

This saves AXIR snapshots to `.alkali-baselines/`. Commit this directory.

### 2. Add a CI step

```yaml
# .github/workflows/visual-regression.yml
name: Visual Regression
on: [pull_request]

jobs:
  check:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Build Alkali
        run: |
          git clone https://github.com/abdousarr/alkali.git /tmp/alkali
          cd /tmp/alkali && swift build -c release
      - name: Check for visual drift
        run: |
          /tmp/alkali/.build/release/alkali preview --all --diff --project-root .
```

### 3. Update baselines when changes are intentional

```bash
alkali preview --all --set-baseline --project-root .
git add .alkali-baselines/
git commit -m "Update visual baselines"
```

## What Gets Detected

Alkali's semantic diffing catches:

- **Modifier changes**: `.padding(16)` → `.padding(24)`, color changes, font changes
- **Structural changes**: Views added/removed from containers
- **Reordering**: Children moved within a container
- **Layout changes**: Frame rects shifted (when using rendered AXIR)

What it intentionally ignores:
- Anti-aliasing differences across macOS versions
- Subpixel rendering variations
- Identical renders from different code paths (refactoring that doesn't change output)

## Perceptual Hashing

For pixel-level comparison (when you have rendered images), Alkali uses a DCT-based perceptual hash:

```swift
import AlkaliPreview

let differ = VisualDiffer()

// Compare two rendered images
let match = differ.perceptualHashesMatch(image1Data, image2Data, threshold: 5)
// threshold = max Hamming distance to consider "same" (0 = identical, 64 = opposite)

// Or compare AXIR trees structurally
let diffs = differ.semanticDiff(old: baselineAXIR, new: currentAXIR)
for diff in diffs {
    switch diff {
    case .modifierChanged(let id, let modifier, let old, let new):
        print("  \(id): \(modifier) changed from \(old) to \(new)")
    case .nodeAdded(let id, let summary):
        print("  + \(summary.viewType) added at \(id)")
    case .nodeRemoved(let id, let summary):
        print("  - \(summary.viewType) removed at \(id)")
    default:
        break
    }
}
```
