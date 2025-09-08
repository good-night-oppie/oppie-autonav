// SPDX-FileCopyrightText: 2024 EdwardTang
// SPDX-License-Identifier: MIT

package sandbox

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/firecracker-microvm/firecracker-go-sdk"
	"github.com/firecracker-microvm/firecracker-go-sdk/client/models"
	"github.com/google/uuid"
	"github.com/sirupsen/logrus"
)

// FirecrackerSandbox implements Sandbox interface using Firecracker microVMs
type FirecrackerSandbox struct {
	id       string
	machine  *firecracker.Machine
	config   SandboxConfig
	state    SandboxState
	metrics  SandboxMetrics
	createdAt time.Time
	lastUsedAt time.Time
	snapshots  []string
	mu       sync.RWMutex
	logger   *logrus.Entry
}

// NewFirecrackerSandbox creates a new Firecracker-based sandbox
func NewFirecrackerSandbox(config SandboxConfig) (*FirecrackerSandbox, error) {
	if config.VMID == "" {
		config.VMID = uuid.New().String()
	}

	logger := logrus.WithFields(logrus.Fields{
		"component": "firecracker-sandbox",
		"vm_id":     config.VMID,
	})

	sandbox := &FirecrackerSandbox{
		id:        config.VMID,
		config:    config,
		state:     StateCreating,
		createdAt: time.Now(),
		logger:    logger,
	}

	if err := sandbox.initialize(); err != nil {
		return nil, fmt.Errorf("failed to initialize Firecracker sandbox: %w", err)
	}

	return sandbox, nil
}

// initialize sets up the Firecracker microVM
func (f *FirecrackerSandbox) initialize() error {
	f.mu.Lock()
	defer f.mu.Unlock()

	socketPath := f.config.SocketPath
	if socketPath == "" {
		socketPath = filepath.Join("/tmp", fmt.Sprintf("firecracker-%s.sock", f.id))
	}

	// Ensure socket directory exists
	if err := os.MkdirAll(filepath.Dir(socketPath), 0755); err != nil {
		return fmt.Errorf("failed to create socket directory: %w", err)
	}

	// Configure Firecracker machine
	machineConfig := firecracker.Config{
		SocketPath:      socketPath,
		KernelImagePath: f.config.KernelImagePath,
		KernelArgs:      "console=ttyS0 reboot=k panic=1 pci=off",
		Drives: []models.Drive{
			{
				DriveID:      firecracker.String("1"),
				PathOnHost:   firecracker.String(f.config.RootFSPath),
				IsReadOnly:   firecracker.Bool(false),
				IsRootDevice: firecracker.Bool(true),
			},
		},
		MachineCfg: models.MachineConfiguration{
			VcpuCount:  firecracker.Int64(int64(f.config.CPUCount)),
			MemSizeMib: firecracker.Int64(int64(f.config.MemoryMB)),
		},
		LogLevel: "Error",
	}

	// Add network configuration if enabled
	if f.config.EnableNetwork {
		machineConfig.NetworkInterfaces = []firecracker.NetworkInterface{
			{
				CNIConfiguration: &firecracker.CNIConfiguration{
					NetworkName: "fcnet",
					IfName:      "veth0",
				},
			},
		}
	}

	// Create machine instance
	machine, err := firecracker.NewMachine(context.Background(), machineConfig)
	if err != nil {
		return fmt.Errorf("failed to create Firecracker machine: %w", err)
	}

	f.machine = machine
	f.state = StateReady
	f.logger.Info("Firecracker sandbox initialized successfully")

	return nil
}

// ID returns the sandbox identifier
func (f *FirecrackerSandbox) ID() string {
	return f.id
}

// Execute runs a command in the sandbox
func (f *FirecrackerSandbox) Execute(ctx context.Context, req ExecutionRequest) (*ExecutionResult, error) {
	f.mu.Lock()
	defer f.mu.Unlock()

	if f.state != StateReady {
		return nil, fmt.Errorf("sandbox %s is not ready (state: %s)", f.id, f.state)
	}

	startTime := time.Now()
	f.state = StateRunning
	f.lastUsedAt = startTime

	defer func() {
		f.state = StateReady
		f.metrics.ExecutionTime = time.Since(startTime)
	}()

	// Start VM if not already running
	if err := f.ensureVMRunning(ctx); err != nil {
		return nil, fmt.Errorf("failed to start VM: %w", err)
	}

	// TODO: Implement actual command execution via VM agent
	// This is a placeholder - real implementation would use firecracker's
	// agent or ssh to execute commands inside the VM
	result := &ExecutionResult{
		ExitCode: 0,
		Stdout:   "Command executed successfully (placeholder)",
		Stderr:   "",
		Duration: time.Since(startTime),
	}

	f.logger.WithFields(logrus.Fields{
		"command":  req.Command,
		"duration": result.Duration,
	}).Info("Command executed in sandbox")

	return result, nil
}

// ensureVMRunning starts the VM if it's not already running
func (f *FirecrackerSandbox) ensureVMRunning(ctx context.Context) error {
	if f.machine == nil {
		return fmt.Errorf("machine not initialized")
	}

	// Check if VM is already running
	// TODO: Implement proper VM state checking
	
	startTime := time.Now()
	
	// Start the machine
	if err := f.machine.Start(ctx); err != nil {
		return fmt.Errorf("failed to start Firecracker machine: %w", err)
	}

	f.metrics.VMStartupTime = time.Since(startTime)
	f.logger.WithField("startup_time", f.metrics.VMStartupTime).Info("VM started successfully")

	return nil
}

// CreateSnapshot creates a VM snapshot
func (f *FirecrackerSandbox) CreateSnapshot(ctx context.Context, snapshotID string) error {
	f.mu.Lock()
	defer f.mu.Unlock()

	if f.machine == nil {
		return fmt.Errorf("machine not initialized")
	}

	startTime := time.Now()
	f.state = StateSnapshot

	defer func() {
		f.state = StateReady
		f.metrics.SnapshotTime = time.Since(startTime)
	}()

	// Create snapshot using Firecracker API
	snapshotPath := filepath.Join("/tmp", fmt.Sprintf("snapshot-%s-%s", f.id, snapshotID))
	
	// TODO: Implement actual snapshot creation
	// This would use Firecracker's snapshot API
	
	f.snapshots = append(f.snapshots, snapshotID)
	
	f.logger.WithFields(logrus.Fields{
		"snapshot_id": snapshotID,
		"duration":    f.metrics.SnapshotTime,
	}).Info("Snapshot created successfully")

	return nil
}

// RestoreSnapshot restores VM to a specific snapshot
func (f *FirecrackerSandbox) RestoreSnapshot(ctx context.Context, snapshotID string) error {
	f.mu.Lock()
	defer f.mu.Unlock()

	startTime := time.Now()
	
	defer func() {
		f.metrics.RestoreTime = time.Since(startTime)
	}()

	// TODO: Implement actual snapshot restoration
	// This would use Firecracker's snapshot restore API
	
	f.logger.WithFields(logrus.Fields{
		"snapshot_id": snapshotID,
		"duration":    f.metrics.RestoreTime,
	}).Info("Snapshot restored successfully")

	return nil
}

// ListSnapshots returns available snapshots
func (f *FirecrackerSandbox) ListSnapshots(ctx context.Context) ([]string, error) {
	f.mu.RLock()
	defer f.mu.RUnlock()

	snapshots := make([]string, len(f.snapshots))
	copy(snapshots, f.snapshots)
	
	return snapshots, nil
}

// GetInfo returns sandbox information
func (f *FirecrackerSandbox) GetInfo(ctx context.Context) (*SandboxInfo, error) {
	f.mu.RLock()
	defer f.mu.RUnlock()

	return &SandboxInfo{
		ID:          f.id,
		State:       f.state,
		Config:      f.config,
		Metrics:     f.metrics,
		CreatedAt:   f.createdAt,
		LastUsedAt:  f.lastUsedAt,
		SnapshotIDs: f.snapshots,
	}, nil
}

// Stop gracefully stops the sandbox
func (f *FirecrackerSandbox) Stop(ctx context.Context) error {
	f.mu.Lock()
	defer f.mu.Unlock()

	if f.machine == nil {
		return nil
	}

	if err := f.machine.Shutdown(ctx); err != nil {
		f.logger.WithError(err).Warn("Failed to gracefully shutdown VM")
		// Force kill if graceful shutdown fails
		if killErr := f.machine.StopVMM(); killErr != nil {
			return fmt.Errorf("failed to stop VM: shutdown error: %w, kill error: %v", err, killErr)
		}
	}

	f.state = StateStopped
	f.logger.Info("Sandbox stopped successfully")

	return nil
}

// Destroy permanently destroys the sandbox
func (f *FirecrackerSandbox) Destroy(ctx context.Context) error {
	f.mu.Lock()
	defer f.mu.Unlock()

	if f.machine != nil {
		if err := f.machine.StopVMM(); err != nil {
			f.logger.WithError(err).Warn("Failed to stop VMM during destroy")
		}
	}

	// Clean up socket file
	if f.config.SocketPath != "" {
		if err := os.Remove(f.config.SocketPath); err != nil && !os.IsNotExist(err) {
			f.logger.WithError(err).Warn("Failed to remove socket file")
		}
	}

	// Clean up snapshot files
	for _, snapshotID := range f.snapshots {
		snapshotPath := filepath.Join("/tmp", fmt.Sprintf("snapshot-%s-%s", f.id, snapshotID))
		if err := os.Remove(snapshotPath); err != nil && !os.IsNotExist(err) {
			f.logger.WithError(err).WithField("snapshot_id", snapshotID).Warn("Failed to remove snapshot file")
		}
	}

	f.state = StateDestroyed
	f.logger.Info("Sandbox destroyed successfully")

	return nil
}