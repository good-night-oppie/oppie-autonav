// SPDX-FileCopyrightText: 2024 EdwardTang
// SPDX-License-Identifier: MIT

package sandbox

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestSandboxConfig validates sandbox configuration
func TestSandboxConfig(t *testing.T) {
	config := SandboxConfig{
		MemoryMB:        512,
		CPUCount:        1,
		DiskSizeMB:      1024,
		TimeoutSeconds:  30,
		EnableNetwork:   true,
		NetworkMode:     "bridge",
		KernelImagePath: "/tmp/kernel.bin",
		RootFSPath:      "/tmp/rootfs.ext4",
		SocketPath:      "/tmp/firecracker.sock",
		VMID:           "test-vm-123",
	}
	
	assert.Equal(t, 512, config.MemoryMB)
	assert.Equal(t, 1, config.CPUCount)
	assert.Equal(t, true, config.EnableNetwork)
	assert.Equal(t, "test-vm-123", config.VMID)
}

// TestExecutionRequest validates execution request structure
func TestExecutionRequest(t *testing.T) {
	req := ExecutionRequest{
		Command:     []string{"echo", "hello world"},
		WorkDir:     "/tmp",
		Environment: map[string]string{"VAR1": "value1"},
		Input:       "test input",
		Timeout:     30 * time.Second,
	}
	
	assert.Equal(t, []string{"echo", "hello world"}, req.Command)
	assert.Equal(t, "/tmp", req.WorkDir)
	assert.Equal(t, "value1", req.Environment["VAR1"])
	assert.Equal(t, 30*time.Second, req.Timeout)
}

// TestSandboxState validates state transitions
func TestSandboxState(t *testing.T) {
	states := []SandboxState{
		StateCreating,
		StateReady,
		StateRunning,
		StateStopped,
		StateDestroyed,
		StateError,
		StateSnapshot,
	}
	
	expectedStates := []string{
		"creating",
		"ready",
		"running",
		"stopped",
		"destroyed",
		"error",
		"snapshot",
	}
	
	for i, state := range states {
		assert.Equal(t, expectedStates[i], string(state))
	}
}

// TestSandboxInfo validates info structure
func TestSandboxInfo(t *testing.T) {
	config := SandboxConfig{
		MemoryMB: 512,
		CPUCount: 1,
		VMID:     "test-vm",
	}
	
	metrics := SandboxMetrics{
		VMStartupTime:   100 * time.Millisecond,
		ExecutionTime:   50 * time.Millisecond,
		TotalMemoryUsed: 256 * 1024 * 1024, // 256MB
	}
	
	now := time.Now()
	info := SandboxInfo{
		ID:         "test-vm",
		State:      StateReady,
		Config:     config,
		Metrics:    metrics,
		CreatedAt:  now,
		LastUsedAt: now,
		SnapshotIDs: []string{"snapshot1", "snapshot2"},
	}
	
	assert.Equal(t, "test-vm", info.ID)
	assert.Equal(t, StateReady, info.State)
	assert.Equal(t, 512, info.Config.MemoryMB)
	assert.Equal(t, 100*time.Millisecond, info.Metrics.VMStartupTime)
	assert.Len(t, info.SnapshotIDs, 2)
}

// MockSandbox implements Sandbox interface for testing
type MockSandbox struct {
	id         string
	state      SandboxState
	snapshots  []string
	destroyed  bool
	executions int
}

func NewMockSandbox(id string) *MockSandbox {
	return &MockSandbox{
		id:        id,
		state:     StateReady,
		snapshots: []string{},
	}
}

func (m *MockSandbox) ID() string {
	return m.id
}

func (m *MockSandbox) Execute(ctx context.Context, req ExecutionRequest) (*ExecutionResult, error) {
	if m.destroyed {
		return nil, assert.AnError
	}
	
	m.executions++
	return &ExecutionResult{
		ExitCode: 0,
		Stdout:   "mock output",
		Stderr:   "",
		Duration: 10 * time.Millisecond,
	}, nil
}

func (m *MockSandbox) CreateSnapshot(ctx context.Context, snapshotID string) error {
	if m.destroyed {
		return assert.AnError
	}
	
	m.snapshots = append(m.snapshots, snapshotID)
	return nil
}

func (m *MockSandbox) RestoreSnapshot(ctx context.Context, snapshotID string) error {
	if m.destroyed {
		return assert.AnError
	}
	
	// Check if snapshot exists
	for _, id := range m.snapshots {
		if id == snapshotID {
			return nil
		}
	}
	
	return assert.AnError
}

func (m *MockSandbox) ListSnapshots(ctx context.Context) ([]string, error) {
	if m.destroyed {
		return nil, assert.AnError
	}
	
	return m.snapshots, nil
}

func (m *MockSandbox) GetInfo(ctx context.Context) (*SandboxInfo, error) {
	if m.destroyed {
		return nil, assert.AnError
	}
	
	return &SandboxInfo{
		ID:          m.id,
		State:       m.state,
		CreatedAt:   time.Now().Add(-time.Hour),
		LastUsedAt:  time.Now(),
		SnapshotIDs: m.snapshots,
	}, nil
}

func (m *MockSandbox) Stop(ctx context.Context) error {
	if m.destroyed {
		return assert.AnError
	}
	
	m.state = StateStopped
	return nil
}

func (m *MockSandbox) Destroy(ctx context.Context) error {
	m.destroyed = true
	m.state = StateDestroyed
	return nil
}

// TestMockSandbox validates mock sandbox functionality
func TestMockSandbox(t *testing.T) {
	ctx := context.Background()
	sandbox := NewMockSandbox("mock-vm")
	
	// Test ID
	assert.Equal(t, "mock-vm", sandbox.ID())
	
	// Test execution
	req := ExecutionRequest{
		Command: []string{"echo", "test"},
		Timeout: 30 * time.Second,
	}
	
	result, err := sandbox.Execute(ctx, req)
	require.NoError(t, err)
	assert.Equal(t, 0, result.ExitCode)
	assert.Equal(t, "mock output", result.Stdout)
	
	// Test snapshot operations
	err = sandbox.CreateSnapshot(ctx, "snap1")
	require.NoError(t, err)
	
	snapshots, err := sandbox.ListSnapshots(ctx)
	require.NoError(t, err)
	assert.Contains(t, snapshots, "snap1")
	
	err = sandbox.RestoreSnapshot(ctx, "snap1")
	require.NoError(t, err)
	
	// Test info
	info, err := sandbox.GetInfo(ctx)
	require.NoError(t, err)
	assert.Equal(t, "mock-vm", info.ID)
	assert.Equal(t, StateReady, info.State)
	
	// Test stop
	err = sandbox.Stop(ctx)
	require.NoError(t, err)
	assert.Equal(t, StateStopped, sandbox.state)
	
	// Test destroy
	err = sandbox.Destroy(ctx)
	require.NoError(t, err)
	assert.True(t, sandbox.destroyed)
	
	// Test operations after destroy
	_, err = sandbox.Execute(ctx, req)
	assert.Error(t, err)
}

// BenchmarkSandboxExecution benchmarks sandbox execution performance
func BenchmarkSandboxExecution(b *testing.B) {
	ctx := context.Background()
	sandbox := NewMockSandbox("bench-vm")
	
	req := ExecutionRequest{
		Command: []string{"echo", "benchmark"},
		Timeout: 30 * time.Second,
	}
	
	b.ResetTimer()
	
	for i := 0; i < b.N; i++ {
		_, err := sandbox.Execute(ctx, req)
		if err != nil {
			b.Fatal(err)
		}
	}
}

