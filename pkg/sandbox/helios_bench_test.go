// Copyright 2025 Good Night Oppie
// SPDX-License-Identifier: Apache-2.0

package sandbox

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func BenchmarkHeliosCommit(b *testing.B) {
	// Skip if helios-cli binary doesn't exist
	binaryPath := "../../bin/helios-cli"
	if _, err := os.Stat(binaryPath); os.IsNotExist(err) {
		b.Skip("helios-cli binary not found, skipping benchmark")
	}

	workDir := "/tmp/helios-bench"
	defer os.RemoveAll(workDir)

	config := HeliosConfig{
		BinaryPath: binaryPath,
		WorkDir:    workDir,
	}

	hm, err := NewHeliosManager(config)
	if err != nil {
		b.Fatalf("Failed to create HeliosManager: %v", err)
	}
	defer hm.Close()

	// Create test file for consistent state
	testFile := filepath.Join(workDir, "benchmark.txt")
	err = os.WriteFile(testFile, []byte("benchmark test content"), 0644)
	if err != nil {
		b.Fatalf("Failed to create test file: %v", err)
	}

	ctx := context.Background()

	b.ResetTimer()
	b.ReportAllocs()

	for i := 0; i < b.N; i++ {
		// Modify content to ensure different snapshots
		content := []byte("benchmark content iteration " + string(rune('A'+i%26)))
		err = os.WriteFile(testFile, content, 0644)
		if err != nil {
			b.Fatalf("Failed to update test file: %v", err)
		}

		start := time.Now()
		_, _, err := hm.Commit(ctx, "benchmark commit")
		if err != nil {
			b.Fatalf("Commit failed: %v", err)
		}
		b.ReportMetric(float64(time.Since(start).Nanoseconds())/1e6, "ms/commit")
	}
}

func BenchmarkHeliosCommitRestore(b *testing.B) {
	// Skip if helios-cli binary doesn't exist
	binaryPath := "../../bin/helios-cli"
	if _, err := os.Stat(binaryPath); os.IsNotExist(err) {
		b.Skip("helios-cli binary not found, skipping benchmark")
	}

	workDir := "/tmp/helios-bench-restore"
	defer os.RemoveAll(workDir)

	config := HeliosConfig{
		BinaryPath: binaryPath,
		WorkDir:    workDir,
	}

	hm, err := NewHeliosManager(config)
	if err != nil {
		b.Fatalf("Failed to create HeliosManager: %v", err)
	}
	defer hm.Close()

	// Create initial state
	testFile := filepath.Join(workDir, "benchmark.txt")
	err = os.WriteFile(testFile, []byte("initial content"), 0644)
	if err != nil {
		b.Fatalf("Failed to create test file: %v", err)
	}

	ctx := context.Background()
	snapshotID, _, err := hm.Commit(ctx, "initial state")
	if err != nil {
		b.Fatalf("Initial commit failed: %v", err)
	}

	b.ResetTimer()
	b.ReportAllocs()

	for i := 0; i < b.N; i++ {
		// Modify state
		modifiedContent := "modified content iteration " + string(rune('A'+i%26))
		err = os.WriteFile(testFile, []byte(modifiedContent), 0644)
		if err != nil {
			b.Fatalf("Failed to modify file: %v", err)
		}

		// Measure restore time
		start := time.Now()
		err = hm.Restore(ctx, snapshotID)
		if err != nil {
			b.Fatalf("Restore failed: %v", err)
		}
		b.ReportMetric(float64(time.Since(start).Nanoseconds())/1e6, "ms/restore")
	}
}