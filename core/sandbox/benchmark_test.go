// SPDX-FileCopyrightText: 2024 EdwardTang
// SPDX-License-Identifier: MIT

package sandbox

import (
	"context"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// BenchmarkVMStartup benchmarks VM startup time
func BenchmarkVMStartup(b *testing.B) {
	template := SandboxConfig{
		MemoryMB:        512,
		CPUCount:        1,
		KernelImagePath: "/tmp/test-kernel",
		RootFSPath:      "/tmp/test-rootfs",
	}

	ctx := context.Background()

	b.ResetTimer()
	b.ReportAllocs()

	for i := 0; i < b.N; i++ {
		config := template
		config.VMID = fmt.Sprintf("bench-vm-%d", i)

		// Create mock sandbox (in real implementation this would be FirecrackerSandbox)
		sandbox := NewMockSandbox(config.VMID)

		// Simulate VM startup time
		startTime := time.Now()
		info, err := sandbox.GetInfo(ctx)
		require.NoError(b, err)
		duration := time.Since(startTime)

		// Record startup time
		b.ReportMetric(float64(duration.Nanoseconds()), "ns/startup")

		// Cleanup
		_ = sandbox.Destroy(ctx)

		// Ensure we meet performance target
		if duration > 100*time.Millisecond {
			b.Errorf("VM startup took %v, target is <100ms", duration)
		}
	}
}

// BenchmarkSnapshotRestore benchmarks snapshot restoration time
func BenchmarkSnapshotRestore(b *testing.B) {
	ctx := context.Background()
	sandbox := NewMockSandbox("snapshot-bench")

	// Create initial snapshot
	err := sandbox.CreateSnapshot(ctx, "bench-snapshot")
	require.NoError(b, err)

	b.ResetTimer()
	b.ReportAllocs()

	for i := 0; i < b.N; i++ {
		startTime := time.Now()
		err := sandbox.RestoreSnapshot(ctx, "bench-snapshot")
		require.NoError(b, err)
		duration := time.Since(startTime)

		// Record restore time
		b.ReportMetric(float64(duration.Nanoseconds()), "ns/restore")

		// Ensure we meet performance target
		if duration > 50*time.Millisecond {
			b.Errorf("Snapshot restore took %v, target is <50ms", duration)
		}
	}
}

// BenchmarkConcurrentVMs benchmarks concurrent VM execution
func BenchmarkConcurrentVMs(b *testing.B) {
	ctx := context.Background()
	pool := NewMockSandboxPool(100)

	config := SandboxConfig{
		MemoryMB: 256,
		CPUCount: 1,
		VMID:     "concurrent-bench",
	}

	req := ExecutionRequest{
		Command: []string{"echo", "hello"},
		Timeout: 30 * time.Second,
	}

	b.ResetTimer()
	b.ReportAllocs()

	b.RunParallel(func(pb *testing.PB) {
		for pb.Next() {
			// Acquire sandbox
			sandbox, err := pool.Acquire(ctx, config)
			if err != nil {
				b.Fatal(err)
			}

			// Execute command
			startTime := time.Now()
			result, err := sandbox.Execute(ctx, req)
			duration := time.Since(startTime)

			if err != nil {
				b.Fatal(err)
			}

			if result.ExitCode != 0 {
				b.Fatalf("Command failed with exit code %d", result.ExitCode)
			}

			// Record execution time
			b.ReportMetric(float64(duration.Nanoseconds()), "ns/exec")

			// Release sandbox
			err = pool.Release(ctx, sandbox)
			if err != nil {
				b.Fatal(err)
			}
		}
	})
}

// BenchmarkMemoryEfficiency benchmarks memory usage efficiency
func BenchmarkMemoryEfficiency(b *testing.B) {
	ctx := context.Background()
	manager := NewSandboxManager(50, SandboxConfig{
		MemoryMB: 256,
		CPUCount: 1,
	})

	defer func() {
		_ = manager.Shutdown(ctx)
	}()

	b.ResetTimer()
	b.ReportAllocs()

	for i := 0; i < b.N; i++ {
		config := SandboxConfig{VMID: fmt.Sprintf("memory-bench-%d", i)}

		// Create sandbox
		sandbox, err := manager.CreateSandbox(ctx, config)
		if err != nil {
			b.Fatal(err)
		}

		// Get memory usage
		info, err := sandbox.GetInfo(ctx)
		if err != nil {
			b.Fatal(err)
		}

		// Report memory metrics
		b.ReportMetric(float64(info.Metrics.TotalMemoryUsed), "bytes/vm")
		b.ReportMetric(float64(info.Metrics.PeakMemoryUsed), "peak-bytes/vm")

		// Cleanup
		err = manager.ReleaseSandbox(ctx, sandbox)
		if err != nil {
			b.Fatal(err)
		}
	}
}

// BenchmarkPoolScaling benchmarks pool scaling behavior
func BenchmarkPoolScaling(b *testing.B) {
	ctx := context.Background()

	poolSizes := []int{5, 10, 25, 50, 100}

	for _, size := range poolSizes {
		b.Run(fmt.Sprintf("PoolSize%d", size), func(b *testing.B) {
			pool := NewMockSandboxPool(size)
			config := SandboxConfig{VMID: "scale-test"}

			b.ResetTimer()
			b.ReportAllocs()

			for i := 0; i < b.N; i++ {
				// Acquire sandbox
				startTime := time.Now()
				sandbox, err := pool.Acquire(ctx, config)
				if err != nil {
					b.Fatal(err)
				}
				acquireTime := time.Since(startTime)

				// Release sandbox
				startTime = time.Now()
				err = pool.Release(ctx, sandbox)
				if err != nil {
					b.Fatal(err)
				}
				releaseTime := time.Since(startTime)

				// Record timing metrics
				b.ReportMetric(float64(acquireTime.Nanoseconds()), "ns/acquire")
				b.ReportMetric(float64(releaseTime.Nanoseconds()), "ns/release")
			}

			_ = pool.Shutdown(ctx)
		})
	}
}

// BenchmarkThroughput benchmarks overall system throughput
func BenchmarkThroughput(b *testing.B) {
	ctx := context.Background()
	manager := NewSandboxManager(20, SandboxConfig{
		MemoryMB: 256,
		CPUCount: 1,
	})

	defer func() {
		_ = manager.Shutdown(ctx)
	}()

	req := ExecutionRequest{
		Command: []string{"echo", "throughput test"},
		Timeout: 10 * time.Second,
	}

	b.ResetTimer()
	b.ReportAllocs()

	// Measure operations per second
	start := time.Now()
	operations := 0

	for i := 0; i < b.N; i++ {
		config := SandboxConfig{VMID: "throughput-test"}

		// Full cycle: create, execute, release
		sandbox, err := manager.CreateSandbox(ctx, config)
		if err != nil {
			b.Fatal(err)
		}

		_, err = sandbox.Execute(ctx, req)
		if err != nil {
			b.Fatal(err)
		}

		err = manager.ReleaseSandbox(ctx, sandbox)
		if err != nil {
			b.Fatal(err)
		}

		operations++
	}

	elapsed := time.Since(start)
	opsPerSec := float64(operations) / elapsed.Seconds()
	b.ReportMetric(opsPerSec, "ops/sec")
}

// BenchmarkResourceContention benchmarks behavior under resource contention
func BenchmarkResourceContention(b *testing.B) {
	ctx := context.Background()
	pool := NewMockSandboxPool(5) // Small pool to create contention

	config := SandboxConfig{VMID: "contention-test"}
	req := ExecutionRequest{
		Command: []string{"sleep", "0.001"}, // Simulate brief work
		Timeout: 5 * time.Second,
	}

	const numWorkers = 20 // More workers than pool capacity

	b.ResetTimer()
	b.ReportAllocs()

	var wg sync.WaitGroup
	contentionTimes := make(chan time.Duration, b.N*numWorkers)

	for i := 0; i < b.N; i++ {
		for w := 0; w < numWorkers; w++ {
			wg.Add(1)
			go func() {
				defer wg.Done()

				startTime := time.Now()

				// Acquire (may wait due to contention)
				sandbox, err := pool.Acquire(ctx, config)
				if err != nil {
					b.Errorf("Failed to acquire: %v", err)
					return
				}

				// Execute
				_, err = sandbox.Execute(ctx, req)
				if err != nil {
					b.Errorf("Failed to execute: %v", err)
				}

				// Release
				err = pool.Release(ctx, sandbox)
				if err != nil {
					b.Errorf("Failed to release: %v", err)
				}

				totalTime := time.Since(startTime)
				contentionTimes <- totalTime
			}()
		}
	}

	wg.Wait()
	close(contentionTimes)

	// Calculate contention metrics
	var totalTime time.Duration
	var maxTime time.Duration
	count := 0

	for duration := range contentionTimes {
		totalTime += duration
		if duration > maxTime {
			maxTime = duration
		}
		count++
	}

	if count > 0 {
		avgTime := totalTime / time.Duration(count)
		b.ReportMetric(float64(avgTime.Nanoseconds()), "avg-ns/op")
		b.ReportMetric(float64(maxTime.Nanoseconds()), "max-ns/op")
	}

	_ = pool.Shutdown(ctx)
}

// BenchmarkSnapshotOperations benchmarks comprehensive snapshot operations
func BenchmarkSnapshotOperations(b *testing.B) {
	ctx := context.Background()
	sandbox := NewMockSandbox("snapshot-ops-bench")

	b.Run("CreateSnapshot", func(b *testing.B) {
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			snapshotID := fmt.Sprintf("create-bench-%d", i)
			startTime := time.Now()
			err := sandbox.CreateSnapshot(ctx, snapshotID)
			duration := time.Since(startTime)

			if err != nil {
				b.Fatal(err)
			}

			b.ReportMetric(float64(duration.Nanoseconds()), "ns/create")

			// Target: snapshot creation should be <100ms
			if duration > 100*time.Millisecond {
				b.Errorf("Snapshot creation took %v, target is <100ms", duration)
			}
		}
	})

	// Create snapshots for restore benchmark
	for i := 0; i < 10; i++ {
		snapshotID := fmt.Sprintf("restore-bench-%d", i)
		err := sandbox.CreateSnapshot(ctx, snapshotID)
		require.NoError(b, err)
	}

	b.Run("RestoreSnapshot", func(b *testing.B) {
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			snapshotID := fmt.Sprintf("restore-bench-%d", i%10)
			startTime := time.Now()
			err := sandbox.RestoreSnapshot(ctx, snapshotID)
			duration := time.Since(startTime)

			if err != nil {
				b.Fatal(err)
			}

			b.ReportMetric(float64(duration.Nanoseconds()), "ns/restore")

			// Target: snapshot restore should be <50ms
			if duration > 50*time.Millisecond {
				b.Errorf("Snapshot restore took %v, target is <50ms", duration)
			}
		}
	})

	b.Run("ListSnapshots", func(b *testing.B) {
		b.ResetTimer()
		for i := 0; i < b.N; i++ {
			startTime := time.Now()
			snapshots, err := sandbox.ListSnapshots(ctx)
			duration := time.Since(startTime)

			if err != nil {
				b.Fatal(err)
			}

			if len(snapshots) == 0 {
				b.Error("No snapshots returned")
			}

			b.ReportMetric(float64(duration.Nanoseconds()), "ns/list")
		}
	})
}