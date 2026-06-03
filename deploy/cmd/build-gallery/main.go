// build-gallery — regenerate the gallery's image list from the images folder.
//
// The gallery page (gallery.html) holds its list of photos in a JS array between
// two sentinel comments:
//
//     // ── @IMAGES_START ──
//     var IMAGES = [ ... ];
//     // ── @IMAGES_END ──
//
// This tool scans the images directory for *.webp files and rewrites everything
// between those two markers. Styling and behaviour in gallery.html are untouched,
// so the page stays the single source of truth for design while the list stays in
// sync with whatever is actually on disk.
//
// Usage (run from the repository root):
//
//     go run ./deploy/cmd/build-gallery                 // scan public/images, update public/gallery.html
//     go run ./deploy/cmd/build-gallery -dir public/images -html public/gallery.html
//     go run ./deploy/cmd/build-gallery -exclude pin,no-pin,wider-angle   // skip the map-pin aerials
//
// Or build a binary once:  go build -o deploy/build-gallery ./deploy/cmd/build-gallery
//
// No external dependencies — standard library only.
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

const (
	startMarker = "// ── @IMAGES_START"
	endMarker   = "// ── @IMAGES_END"
	indent      = "    " // matches the 4-space indentation inside <script>
	rule        = " ──────────────────────────────────────────────────────"
)

func main() {
	dir := flag.String("dir", "/home/coder/casacactusbuenavista/public/images", "folder to scan for .webp images")
	htmlPath := flag.String("html", "/home/coder/casacactusbuenavista/public/gallery.html", "gallery HTML file to update")
	excludeCSV := flag.String("exclude", "", "comma-separated substrings; any filename containing one is skipped")
	flag.Parse()

	excludes := splitCSV(*excludeCSV)

	names, err := collectWebp(*dir, excludes)
	if err != nil {
		fail("cannot read %s: %v", *dir, err)
	}
	if len(names) == 0 {
		fail("no .webp files found in %s", *dir)
	}

	html, err := os.ReadFile(*htmlPath)
	if err != nil {
		fail("cannot read %s: %v", *htmlPath, err)
	}

	updated, err := replaceBlock(string(html), buildBlock(*dir, names))
	if err != nil {
		fail("%v", err)
	}

	if err := os.WriteFile(*htmlPath, []byte(updated), 0o644); err != nil {
		fail("cannot write %s: %v", *htmlPath, err)
	}
	fmt.Printf("%s updated — %d images\n", *htmlPath, len(names))
}

// collectWebp returns the sorted, de-duplicated basenames (without extension) of
// every .webp file in dir, skipping any whose name contains an excluded substring.
func collectWebp(dir string, excludes []string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	seen := make(map[string]bool)
	var names []string
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		name := e.Name()
		if !strings.EqualFold(filepath.Ext(name), ".webp") {
			continue
		}
		base := strings.TrimSuffix(name, filepath.Ext(name))
		if seen[base] || matchesAny(base, excludes) {
			continue
		}
		seen[base] = true
		names = append(names, base)
	}
	sort.Strings(names)
	return names, nil
}

// buildBlock renders the full marker-to-marker block, including both sentinels.
func buildBlock(dir string, names []string) string {
	var b strings.Builder
	b.WriteString(indent + startMarker + rule + "\n")
	b.WriteString(indent + "// Auto-generated from " + dir + " by deploy/cmd/build-gallery. Do not hand-edit;\n")
	b.WriteString(indent + "// run `go run ./deploy/cmd/build-gallery` from the repo root to refresh.\n")
	b.WriteString(indent + "var IMAGES = [\n")
	for i, n := range names {
		comma := ","
		if i == len(names)-1 {
			comma = ""
		}
		fmt.Fprintf(&b, "%s  %q%s\n", indent, n, comma)
	}
	b.WriteString(indent + "];\n")
	b.WriteString(indent + endMarker + rule)
	return b.String()
}

// replaceBlock swaps the text between (and including) the marker lines for newBlock.
func replaceBlock(html, newBlock string) (string, error) {
	si := strings.Index(html, startMarker)
	ei := strings.Index(html, endMarker)
	if si == -1 || ei == -1 {
		return "", fmt.Errorf("markers %q / %q not found — is this the right gallery file?", startMarker, endMarker)
	}
	if ei < si {
		return "", fmt.Errorf("end marker appears before start marker")
	}
	lineStart := strings.LastIndexByte(html[:si], '\n') + 1 // start of the START marker's line
	lineEnd := ei
	if nl := strings.IndexByte(html[ei:], '\n'); nl != -1 {
		lineEnd += nl // end of the END marker's line (exclusive of the newline)
	} else {
		lineEnd = len(html)
	}
	return html[:lineStart] + newBlock + html[lineEnd:], nil
}

func splitCSV(s string) []string {
	var out []string
	for _, p := range strings.Split(s, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}

func matchesAny(s string, subs []string) bool {
	for _, sub := range subs {
		if strings.Contains(s, sub) {
			return true
		}
	}
	return false
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}