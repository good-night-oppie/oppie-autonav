// SPDX-FileCopyrightText: 2024 EdwardTang
// SPDX-License-Identifier: MIT

// Package sandbox provides hot-loop virtualization for MCTS exploration
package sandbox

import (
	"context"
	"time"
)

// SandboxConfig defines configuration for sandbox creation
type SandboxConfig struct {
	// Resource limits
	MemoryMB       int    `json:"memory_mb"`
	CPUCount       int    `json:"cpu_count"`
	DiskSizeMB     int    `json:"disk_size_mb"`
	TimeoutSeconds int    `json:"timeout_seconds"`
	
	// Network configuration
	EnableNetwork bool   `json:"enable_network"`
	NetworkMode   string `json:"network_mode"` // "bridge", "none", "host"
	
	// Firecracker specific
	KernelImagePath string `json:"kernel_image_path"`
	RootFSPath      string `json:"rootfs_path"`
	SocketPath      string `json:"socket_path"`
	
	// VM identification
	VMID          string `json:"vm_id"`
	SnapshotID    string `json:"snapshot_id,omitempty"`
}

// ExecutionRequest represents a command to execute in sandbox
type ExecutionRequest struct {
	Command     []string          `json:"command"`
	WorkDir     string            `json:"work_dir"`
	Environment map[string]string `json:"environment"`
	Input       string            `json:"input"`
	Timeout     time.Duration     `json:"timeout"`
}

// ExecutionResult contains results from sandbox execution
type ExecutionResult struct {
	ExitCode    int           `json:"exit_code"`
	Stdout      string        `json:"stdout"`
	Stderr      string        `json:"stderr"`
	Duration    time.Duration `json:"duration"`
	MemoryUsed  int64         `json:"memory_used"`
	CPUUsed     float64       `json:"cpu_used"`
	Error       error         `json:"error,omitempty"`
}

// SandboxMetrics tracks performance and usage statistics
type SandboxMetrics struct {
	VMStartupTime    time.Duration `json:"vm_startup_time"`
	SnapshotTime     time.Duration `json:"snapshot_time"`
	RestoreTime      time.Duration `json:"restore_time"`
	ExecutionTime    time.Duration `json:"execution_time"`
	TotalMemoryUsed  int64         `json:"total_memory_used"`
	PeakMemoryUsed   int64         `json:"peak_memory_used"`
	CPUUtilization   float64       `json:"cpu_utilization"`
	NetworkBytesIn   int64         `json:"network_bytes_in"`
	NetworkBytesOut  int64         `json:"network_bytes_out"`
	ErrorCount       int           `json:"error_count"`
	RestartCount     int           `json:"restart_count"`
}

// SandboxState represents the current state of a sandbox
type SandboxState string

const (
	StateCreating  SandboxState = "creating"
	StateReady     SandboxState = "ready" 
	StateRunning   SandboxState = "running"
	StateStopped   SandboxState = "stopped"
	StateDestroyed SandboxState = "destroyed"
	StateError     SandboxState = "error"
	StateSnapshot  SandboxState = "snapshot"
)

// SandboxInfo provides information about a sandbox instance
type SandboxInfo struct {
	ID           string         `json:"id"`
	State        SandboxState   `json:"state"`
	Config       SandboxConfig  `json:"config"`
	Metrics      SandboxMetrics `json:"metrics"`
	CreatedAt    time.Time      `json:"created_at"`
	LastUsedAt   time.Time      `json:"last_used_at"`
	SnapshotIDs  []string       `json:"snapshot_ids"`
	Error        error          `json:"error,omitempty"`
}

// Sandbox represents a hot-loop virtualization instance
type Sandbox interface {
	// ID returns the unique identifier for this sandbox
	ID() string
	
	// Execute runs a command in the sandbox and returns results
	Execute(ctx context.Context, req ExecutionRequest) (*ExecutionResult, error)
	
	// CreateSnapshot creates a snapshot of current VM state
	CreateSnapshot(ctx context.Context, snapshotID string) error
	
	// RestoreSnapshot restores VM to a specific snapshot
	RestoreSnapshot(ctx context.Context, snapshotID string) error
	
	// ListSnapshots returns available snapshots
	ListSnapshots(ctx context.Context) ([]string, error)
	
	// GetInfo returns current sandbox information
	GetInfo(ctx context.Context) (*SandboxInfo, error)
	
	// Stop gracefully stops the sandbox
	Stop(ctx context.Context) error
	
	// Destroy permanently destroys the sandbox and cleanup resources
	Destroy(ctx context.Context) error
}

// SandboxPool manages a pool of pre-warmed sandbox instances
type SandboxPool interface {
	// Acquire gets an available sandbox from the pool
	Acquire(ctx context.Context, config SandboxConfig) (Sandbox, error)
	
	// Release returns a sandbox to the pool for reuse
	Release(ctx context.Context, sandbox Sandbox) error
	
	// GetPoolStats returns pool utilization statistics
	GetPoolStats(ctx context.Context) (*PoolStats, error)
	
	// Cleanup removes unused sandboxes and resources
	Cleanup(ctx context.Context) error
	
	// Shutdown gracefully shuts down the pool
	Shutdown(ctx context.Context) error
}

// PoolStats provides pool utilization metrics
type PoolStats struct {
	TotalCapacity     int           `json:"total_capacity"`
	AvailableCount    int           `json:"available_count"`
	ActiveCount       int           `json:"active_count"`
	CreatedCount      int64         `json:"created_count"`
	DestroyedCount    int64         `json:"destroyed_count"`
	AverageStartupTime time.Duration `json:"average_startup_time"`
	PoolUtilization   float64       `json:"pool_utilization"`
	ErrorRate         float64       `json:"error_rate"`
}

// SandboxManager orchestrates sandbox lifecycle and pool management
type SandboxManager interface {
	// CreateSandbox creates a new sandbox with specified config
	CreateSandbox(ctx context.Context, config SandboxConfig) (Sandbox, error)
	
	// GetSandbox retrieves an existing sandbox by ID
	GetSandbox(ctx context.Context, id string) (Sandbox, error)
	
	// ListSandboxes returns all managed sandboxes
	ListSandboxes(ctx context.Context) ([]*SandboxInfo, error)
	
	// GetPool returns the sandbox pool
	GetPool() SandboxPool
	
	// GetMetrics returns aggregated metrics across all sandboxes
	GetMetrics(ctx context.Context) (*SandboxMetrics, error)
	
	// Shutdown gracefully shuts down all sandboxes and resources
	Shutdown(ctx context.Context) error
}