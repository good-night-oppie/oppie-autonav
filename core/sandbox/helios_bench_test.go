// SPDX-FileCopyrightText: 2024 EdwardTang
// SPDX-License-Identifier: MIT

package sandbox

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// BenchmarkHeliosCommit benchmarks actual Helios commit operations
func BenchmarkHeliosCommit(b *testing.B) {
	if testing.Short() {
		b.Skip("skipping benchmark in short mode")
	}

	// Check if Helios CLI is available
	heliosPath := os.Getenv("HELIOS_CLI_PATH")
	if heliosPath == "" {
		heliosPath = "helios" // Default to PATH
	}

	// Create temporary work directory
	tempDir, err := os.MkdirTemp("", "helios-bench-*")
	require.NoError(b, err)
	defer os.RemoveAll(tempDir)

	// Initialize Helios in temp directory
	config := HeliosConfig{
		BinaryPath: heliosPath,
		WorkDir:    tempDir,
	}

	manager, err := NewHeliosManager(config)
	if err != nil {
		b.Skipf("Helios CLI not available: %v", err)
	}

	ctx := context.Background()

	b.ResetTimer()
	b.ReportAllocs()

	commitTimes := make([]time.Duration, 0, b.N)

	for i := 0; i < b.N; i++ {
		// Create test file for each commit
		testFile := filepath.Join(tempDir, "test-file", "benchmark.txt")
		err = os.MkdirAll(filepath.Dir(testFile), 0755)
		require.NoError(b, err)

		err = os.WriteFile(testFile, []byte("benchmark data"), 0644)
		require.NoError(b, err)

		// Measure commit time
		startTime := time.Now()
		snapshotID, metrics, err := manager.Commit(ctx, "benchmark snapshot")
		commitTime := time.Since(startTime)

		if err != nil {
			b.Fatalf("Commit failed: %v", err)
		}

		if snapshotID == "" {
			b.Fatal("Empty snapshot ID returned")
		}

		if metrics == nil {
			b.Fatal("No metrics returned")
		}

		commitTimes = append(commitTimes, commitTime)

		// Report individual commit time
		b.ReportMetric(float64(commitTime.Nanoseconds()), "ns/commit")

		// Target validation: should be <50ms
		if commitTime > 50*time.Millisecond {
			b.Logf("WARNING: Commit took %v, target is <50ms", commitTime)
		}

		// Cleanup for next iteration
		os.Remove(testFile)
	}

	// Calculate and report statistics
	if len(commitTimes) > 0 {
		var totalTime time.Duration
		var minTime = commitTimes[0]
		var maxTime = commitTimes[0]

		for _, t := range commitTimes {
			totalTime += t
			if t < minTime {
				minTime = t
			}
			if t > maxTime {
				maxTime = t
			}
		}

		avgTime := totalTime / time.Duration(len(commitTimes))
		
		b.ReportMetric(float64(avgTime.Nanoseconds()), "avg-ns/commit")
		b.ReportMetric(float64(minTime.Nanoseconds()), "min-ns/commit") 
		b.ReportMetric(float64(maxTime.Nanoseconds()), "max-ns/commit")
		
		b.Logf("Commit Performance: avg=%v, min=%v, max=%v", avgTime, minTime, maxTime)
	}
}

// BenchmarkHeliosRestore benchmarks snapshot restoration operations
func BenchmarkHeliosRestore(b *testing.B) {
	if testing.Short() {
		b.Skip("skipping benchmark in short mode")
	}

	heliosPath := os.Getenv("HELIOS_CLI_PATH")
	if heliosPath == "" {
		heliosPath = "helios"
	}

	tempDir, err := os.MkdirTemp("", "helios-restore-bench-*")
	require.NoError(b, err)
	defer os.RemoveAll(tempDir)

	config := HeliosConfig{
		BinaryPath: heliosPath,
		WorkDir:    tempDir,
	}

	manager, err := NewHeliosManager(config)
	if err != nil {
		b.Skipf("Helios CLI not available: %v", err)
	}

	ctx := context.Background()

	// Initialize Helios storage
	err = manager.Initialize(ctx)
	if err != nil {
		b.Skipf("Failed to initialize Helios: %v", err)
	}

	// Create test data
	testFile := filepath.Join(tempDir, "test-file", "restore-test.txt")
	err = os.MkdirAll(filepath.Dir(testFile), 0755)
	require.NoError(b, err)

	err = os.WriteFile(testFile, []byte("restore benchmark data"), 0644)
	require.NoError(b, err)

	// Create base snapshot
	baseSnapshot, _, err := manager.CreateSnapshot(ctx, "base-snapshot")
	require.NoError(b, err)

	b.ResetTimer()
	b.ReportAllocs()

	restoreTimes := make([]time.Duration, 0, b.N)

	for i := 0; i < b.N; i++ {
		// Measure restore time
		startTime := time.Now()
		metrics, err := manager.RestoreSnapshot(ctx, baseSnapshot)
		restoreTime := time.Since(startTime)

		if err != nil {
			b.Fatalf("Restore failed: %v", err)
		}

		if metrics == nil {
			b.Fatal("No metrics returned")
		}

		restoreTimes = append(restoreTimes, restoreTime)

		// Report individual restore time
		b.ReportMetric(float64(restoreTime.Nanoseconds()), "ns/restore")

		// Target validation: should be <25ms
		if restoreTime > 25*time.Millisecond {
			b.Logf("WARNING: Restore took %v, target is <25ms", restoreTime)
		}
	}

	// Calculate and report statistics
	if len(restoreTimes) > 0 {
		var totalTime time.Duration
		var minTime = restoreTimes[0]
		var maxTime = restoreTimes[0]

		for _, t := range restoreTimes {
			totalTime += t
			if t < minTime {
				minTime = t
			}
			if t > maxTime {
				maxTime = t
			}
		}

		avgTime := totalTime / time.Duration(len(restoreTimes))
		
		b.ReportMetric(float64(avgTime.Nanoseconds()), "avg-ns/restore")
		b.ReportMetric(float64(minTime.Nanoseconds()), "min-ns/restore")
		b.ReportMetric(float64(maxTime.Nanoseconds()), "max-ns/restore")
		
		b.Logf("Restore Performance: avg=%v, min=%v, max=%v", avgTime, minTime, maxTime)
	}
}

// BenchmarkHeliosCommitRestore benchmarks full commit+restore cycle
func BenchmarkHeliosCommitRestore(b *testing.B) {
	if testing.Short() {
		b.Skip("skipping benchmark in short mode")
	}

	heliosPath := os.Getenv("HELIOS_CLI_PATH")
	if heliosPath == "" {
		heliosPath = "helios"
	}

	tempDir, err := os.MkdirTemp("", "helios-cycle-bench-*")
	require.NoError(b, err)
	defer os.RemoveAll(tempDir)

	config := HeliosConfig{
		BinaryPath: heliosPath,
		WorkDir:    tempDir,
	}

	manager, err := NewHeliosManager(config)
	if err != nil {
		b.Skipf("Helios CLI not available: %v", err)
	}

	ctx := context.Background()

	err = manager.Initialize(ctx)
	if err != nil {
		b.Skipf("Failed to initialize Helios: %v", err)
	}

	b.ResetTimer()
	b.ReportAllocs()

	cycleTimes := make([]time.Duration, 0, b.N)

	for i := 0; i < b.N; i++ {
		// Create test file for each cycle
		testFile := filepath.Join(tempDir, "test-file", "cycle-test.txt")
		err = os.MkdirAll(filepath.Dir(testFile), 0755)
		require.NoError(b, err)

		err = os.WriteFile(testFile, []byte("cycle benchmark data"), 0644)
		require.NoError(b, err)

		// Measure full cycle: commit + restore
		startTime := time.Now()

		// Commit
		snapshotID, commitMetrics, err := manager.CreateSnapshot(ctx, "cycle-snapshot")
		if err != nil {
			b.Fatalf("Commit failed: %v", err)
		}

		// Restore
		_, restoreMetrics, err := manager.RestoreSnapshot(ctx, snapshotID)
		if err != nil {
			b.Fatalf("Restore failed: %v", err)
		}

		cycleTime := time.Since(startTime)
		cycleTimes = append(cycleTimes, cycleTime)

		// Report cycle metrics
		b.ReportMetric(float64(cycleTime.Nanoseconds()), "ns/cycle")
		
		if commitMetrics != nil {
			b.ReportMetric(float64(commitMetrics.CommitTime.Nanoseconds()), "ns/commit-part")
		}
		
		if restoreMetrics != nil {
			b.ReportMetric(float64(restoreMetrics.RestoreTime.Nanoseconds()), "ns/restore-part")
		}

		// MCTS target validation: full cycle should be <100ms
		if cycleTime > 100*time.Millisecond {
			b.Logf("WARNING: Full cycle took %v, MCTS target is <100ms", cycleTime)
		}

		// Cleanup
		os.Remove(testFile)
	}

	// Calculate and report cycle statistics
	if len(cycleTimes) > 0 {
		var totalTime time.Duration
		var minTime = cycleTimes[0]
		var maxTime = cycleTimes[0]

		for _, t := range cycleTimes {
			totalTime += t
			if t < minTime {
				minTime = t
			}
			if t > maxTime {
				maxTime = t
			}
		}

		avgTime := totalTime / time.Duration(len(cycleTimes))
		
		b.ReportMetric(float64(avgTime.Nanoseconds()), "avg-ns/cycle")
		b.ReportMetric(float64(minTime.Nanoseconds()), "min-ns/cycle")
		b.ReportMetric(float64(maxTime.Nanoseconds()), "max-ns/cycle")
		
		b.Logf("MCTS Cycle Performance: avg=%v, min=%v, max=%v", avgTime, minTime, maxTime)
		
		// Final MCTS validation
		if avgTime <= 100*time.Millisecond {
			b.Logf("✅ MCTS TARGET MET: Average cycle time %v <= 100ms", avgTime)
		} else {
			b.Logf("❌ MCTS TARGET MISSED: Average cycle time %v > 100ms", avgTime)
		}
	}
}

// BenchmarkFirecrackerVMStartup benchmarks Firecracker VM creation
func BenchmarkFirecrackerVMStartup(b *testing.B) {
	if testing.Short() {
		b.Skip("skipping benchmark in short mode")
	}

	// Check for required Firecracker assets
	kernelPath := os.Getenv("FIRECRACKER_KERNEL_PATH")
	rootfsPath := os.Getenv("FIRECRACKER_ROOTFS_PATH")
	
	if kernelPath == "" || rootfsPath == "" {
		b.Skip("FIRECRACKER_KERNEL_PATH and FIRECRACKER_ROOTFS_PATH must be set for VM benchmarks")
	}

	config := SandboxConfig{
		MemoryMB:        256,
		CPUCount:        1,
		KernelImagePath: kernelPath,
		RootFSPath:      rootfsPath,
	}

	b.ResetTimer()
	b.ReportAllocs()

	startupTimes := make([]time.Duration, 0, b.N)

	for i := 0; i < b.N; i++ {
		// Measure VM creation time
		startTime := time.Now()
		
		sandbox, err := NewFirecrackerSandbox(config)
		if err != nil {
			b.Skipf("Failed to create Firecracker sandbox: %v", err)
		}
		
		startupTime := time.Since(startTime)
		startupTimes = append(startupTimes, startupTime)

		// Report startup time
		b.ReportMetric(float64(startupTime.Nanoseconds()), "ns/startup")

		// Target validation: should be <100ms
		if startupTime > 100*time.Millisecond {
			b.Logf("WARNING: VM startup took %v, target is <100ms", startupTime)
		}

		// Cleanup
		ctx := context.Background()
		_ = sandbox.Destroy(ctx)
	}

	// Calculate and report startup statistics
	if len(startupTimes) > 0 {
		var totalTime time.Duration
		var minTime = startupTimes[0]
		var maxTime = startupTimes[0]

		for _, t := range startupTimes {
			totalTime += t
			if t < minTime {
				minTime = t
			}
			if t > maxTime {
				maxTime = t
			}
		}

		avgTime := totalTime / time.Duration(len(startupTimes))
		
		b.ReportMetric(float64(avgTime.Nanoseconds()), "avg-ns/startup")
		b.ReportMetric(float64(minTime.Nanoseconds()), "min-ns/startup")
		b.ReportMetric(float64(maxTime.Nanoseconds()), "max-ns/startup")
		
		b.Logf("VM Startup Performance: avg=%v, min=%v, max=%v", avgTime, minTime, maxTime)
	}
}

// TestBenchmarkSanity ensures benchmark functions work correctly
func TestBenchmarkSanity(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping sanity test in short mode")
	}

	// Test that benchmarks can run without panic
	t.Run("HeliosCommit", func(t *testing.T) {
		result := testing.Benchmark(BenchmarkHeliosCommit)
		if result.N == 0 {
			t.Skip("Benchmark skipped (likely missing Helios CLI)")
		}
		t.Logf("HeliosCommit benchmark ran %d iterations", result.N)
	})

	t.Run("HeliosRestore", func(t *testing.T) {
		result := testing.Benchmark(BenchmarkHeliosRestore)
		if result.N == 0 {
			t.Skip("Benchmark skipped (likely missing Helios CLI)")
		}
		t.Logf("HeliosRestore benchmark ran %d iterations", result.N)
	})

	t.Run("HeliosCommitRestore", func(t *testing.T) {
		result := testing.Benchmark(BenchmarkHeliosCommitRestore)
		if result.N == 0 {
			t.Skip("Benchmark skipped (likely missing Helios CLI)")
		}
		t.Logf("HeliosCommitRestore benchmark ran %d iterations", result.N)
	})
}