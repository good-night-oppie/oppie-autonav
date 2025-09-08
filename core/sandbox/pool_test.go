// SPDX-FileCopyrightText: 2024 EdwardTang
// SPDX-License-Identifier: MIT

package sandbox

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// MockSandboxPool implements SandboxPool for testing
type MockSandboxPool struct {
	available   chan Sandbox
	maxSize     int
	created     int
	destroyed   int
	errorRate   float64
	mu          sync.RWMutex
}

func NewMockSandboxPool(maxSize int) *MockSandboxPool {
	return &MockSandboxPool{
		available: make(chan Sandbox, maxSize),
		maxSize:   maxSize,
	}
}

func (p *MockSandboxPool) Acquire(ctx context.Context, config SandboxConfig) (Sandbox, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	
	select {
	case sandbox := <-p.available:
		return sandbox, nil
		
	default:
		if p.created < p.maxSize {
			sandbox := NewMockSandbox(config.VMID)
			p.created++
			return sandbox, nil
		}
		
		// Wait for available sandbox
		select {
		case sandbox := <-p.available:
			return sandbox, nil
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}
}

func (p *MockSandboxPool) Release(ctx context.Context, sandbox Sandbox) error {
	select {
	case p.available <- sandbox:
		return nil
	default:
		// Pool full, destroy sandbox
		return sandbox.Destroy(ctx)
	}
}

func (p *MockSandboxPool) GetPoolStats(ctx context.Context) (*PoolStats, error) {
	p.mu.RLock()
	defer p.mu.RUnlock()
	
	return &PoolStats{
		TotalCapacity:      p.maxSize,
		AvailableCount:     len(p.available),
		ActiveCount:        p.created - len(p.available),
		CreatedCount:       int64(p.created),
		DestroyedCount:     int64(p.destroyed),
		AverageStartupTime: 100 * time.Millisecond,
		ErrorRate:          p.errorRate,
	}, nil
}

func (p *MockSandboxPool) Cleanup(ctx context.Context) error {
	return nil
}

func (p *MockSandboxPool) Shutdown(ctx context.Context) error {
	close(p.available)
	return nil
}

// TestMockSandboxPool validates mock pool functionality
func TestMockSandboxPool(t *testing.T) {
	ctx := context.Background()
	pool := NewMockSandboxPool(3)
	
	// Test acquiring sandboxes
	config := SandboxConfig{VMID: "test-vm-1"}
	sandbox1, err := pool.Acquire(ctx, config)
	require.NoError(t, err)
	assert.Equal(t, "test-vm-1", sandbox1.ID())
	
	// Test releasing sandbox
	err = pool.Release(ctx, sandbox1)
	require.NoError(t, err)
	
	// Test pool stats
	stats, err := pool.GetPoolStats(ctx)
	require.NoError(t, err)
	assert.Equal(t, 3, stats.TotalCapacity)
	assert.Equal(t, int64(1), stats.CreatedCount)
	
	// Test shutdown
	err = pool.Shutdown(ctx)
	require.NoError(t, err)
}

// TestPoolConcurrency tests concurrent access to sandbox pool
func TestPoolConcurrency(t *testing.T) {
	ctx := context.Background()
	pool := NewMockSandboxPool(5)
	
	const numWorkers = 10
	const operationsPerWorker = 50
	
	var wg sync.WaitGroup
	errors := make(chan error, numWorkers)
	
	// Start concurrent workers
	for i := 0; i < numWorkers; i++ {
		wg.Add(1)
		go func(workerID int) {
			defer wg.Done()
			
			for j := 0; j < operationsPerWorker; j++ {
				config := SandboxConfig{VMID: "worker-vm"}
				
				// Acquire sandbox
				sandbox, err := pool.Acquire(ctx, config)
				if err != nil {
					errors <- err
					return
				}
				
				// Simulate some work
				time.Sleep(time.Millisecond)
				
				// Release sandbox
				if err := pool.Release(ctx, sandbox); err != nil {
					errors <- err
					return
				}
			}
		}(i)
	}
	
	wg.Wait()
	close(errors)
	
	// Check for errors
	for err := range errors {
		t.Errorf("Concurrent operation failed: %v", err)
	}
	
	// Verify pool stats
	stats, err := pool.GetPoolStats(ctx)
	require.NoError(t, err)
	assert.LessOrEqual(t, stats.ActiveCount, 5) // Should not exceed max size
}

// TestPoolCapacityLimits tests pool capacity enforcement
func TestPoolCapacityLimits(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
	defer cancel()
	
	pool := NewMockSandboxPool(2) // Small pool for testing
	
	// Acquire up to max capacity
	sandboxes := make([]Sandbox, 0, 2)
	for i := 0; i < 2; i++ {
		config := SandboxConfig{VMID: "limit-test"}
		sandbox, err := pool.Acquire(ctx, config)
		require.NoError(t, err)
		sandboxes = append(sandboxes, sandbox)
	}
	
	// Try to acquire beyond capacity (should timeout)
	config := SandboxConfig{VMID: "should-timeout"}
	_, err := pool.Acquire(ctx, config)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "context deadline exceeded")
	
	// Release one sandbox
	err = pool.Release(ctx, sandboxes[0])
	require.NoError(t, err)
	
	// Now acquiring should work
	sandbox, err := pool.Acquire(ctx, config)
	require.NoError(t, err)
	assert.NotNil(t, sandbox)
}

// BenchmarkPoolAcquireRelease benchmarks pool acquire/release operations
func BenchmarkPoolAcquireRelease(b *testing.B) {
	ctx := context.Background()
	pool := NewMockSandboxPool(10)
	
	config := SandboxConfig{VMID: "bench-vm"}
	
	b.ResetTimer()
	
	for i := 0; i < b.N; i++ {
		sandbox, err := pool.Acquire(ctx, config)
		if err != nil {
			b.Fatal(err)
		}
		
		err = pool.Release(ctx, sandbox)
		if err != nil {
			b.Fatal(err)
		}
	}
}

// BenchmarkPoolConcurrentAccess benchmarks concurrent pool access
func BenchmarkPoolConcurrentAccess(b *testing.B) {
	ctx := context.Background()
	pool := NewMockSandboxPool(20)
	
	config := SandboxConfig{VMID: "concurrent-bench"}
	
	b.ResetTimer()
	
	b.RunParallel(func(pb *testing.PB) {
		for pb.Next() {
			sandbox, err := pool.Acquire(ctx, config)
			if err != nil {
				b.Fatal(err)
			}
			
			// Simulate brief work
			time.Sleep(time.Microsecond)
			
			err = pool.Release(ctx, sandbox)
			if err != nil {
				b.Fatal(err)
			}
		}
	})
}

// TestPoolStats validates pool statistics reporting
func TestPoolStats(t *testing.T) {
	ctx := context.Background()
	pool := NewMockSandboxPool(5)
	
	// Get initial stats
	stats, err := pool.GetPoolStats(ctx)
	require.NoError(t, err)
	assert.Equal(t, 5, stats.TotalCapacity)
	assert.Equal(t, 0, stats.AvailableCount)
	assert.Equal(t, int64(0), stats.CreatedCount)
	
	// Acquire some sandboxes
	sandboxes := make([]Sandbox, 3)
	for i := 0; i < 3; i++ {
		config := SandboxConfig{VMID: "stats-test"}
		sandbox, err := pool.Acquire(ctx, config)
		require.NoError(t, err)
		sandboxes[i] = sandbox
	}
	
	// Check stats after acquisition
	stats, err = pool.GetPoolStats(ctx)
	require.NoError(t, err)
	assert.Equal(t, int64(3), stats.CreatedCount)
	assert.Equal(t, 3, stats.ActiveCount)
	
	// Release sandboxes back to pool
	for _, sandbox := range sandboxes {
		err = pool.Release(ctx, sandbox)
		require.NoError(t, err)
	}
	
	// Check final stats
	stats, err = pool.GetPoolStats(ctx)
	require.NoError(t, err)
	assert.Equal(t, 3, stats.AvailableCount)
	assert.Equal(t, 0, stats.ActiveCount)
}