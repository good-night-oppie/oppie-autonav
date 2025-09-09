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

	"github.com/google/uuid"
	"github.com/sirupsen/logrus"
)

// HeliosFirecrackerSandbox combines Helios state management with Firecracker VMs
type HeliosFirecrackerSandbox struct {
	id            string
	firecrackerVM *FirecrackerSandbox
	heliosManager *HeliosManager
	workDir       string
	mu            sync.RWMutex
	logger        *logrus.Entry
	state         SandboxState
	createdAt     time.Time
	lastUsedAt    time.Time
}

// HeliosFirecrackerConfig combines configuration for both Helios and Firecracker
type HeliosFirecrackerConfig struct {
	SandboxConfig // Firecracker configuration
	HeliosConfig  // Helios configuration
}

// NewHeliosFirecrackerSandbox creates a new integrated sandbox
func NewHeliosFirecrackerSandbox(config HeliosFirecrackerConfig) (*HeliosFirecrackerSandbox, error) {
	if config.VMID == "" {
		config.VMID = uuid.New().String()
	}

	// Create unique work directory for this sandbox
	workDir := filepath.Join("/tmp", "helios-fc-sandbox", config.VMID)
	if err := os.MkdirAll(workDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create work directory: %w", err)
	}

	// Update Helios config to use sandbox-specific directory
	config.HeliosConfig.WorkDir = workDir

	logger := logrus.WithFields(logrus.Fields{
		"component": "helios-firecracker-sandbox",
		"vm_id":     config.VMID,
		"work_dir":  workDir,
	})

	sandbox := &HeliosFirecrackerSandbox{
		id:         config.VMID,
		workDir:    workDir,
		state:      StateCreating,
		createdAt:  time.Now(),
		logger:     logger,
	}

	// Initialize Firecracker VM
	firecrackerVM, err := NewFirecrackerSandbox(config.SandboxConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to create Firecracker sandbox: %w", err)
	}
	sandbox.firecrackerVM = firecrackerVM

	// Initialize Helios manager
	heliosManager, err := NewHeliosManager(config.HeliosConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to create Helios manager: %w", err)
	}
	sandbox.heliosManager = heliosManager

	// Initialize Helios storage
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := heliosManager.Initialize(ctx); err != nil {
		logger.WithError(err).Warn("Failed to initialize Helios storage - continuing without state management")
	}

	sandbox.state = StateReady
	logger.Info("Integrated Helios+Firecracker sandbox initialized")

	return sandbox, nil
}

// ID returns the sandbox identifier
func (hf *HeliosFirecrackerSandbox) ID() string {
	return hf.id
}

// Execute runs a command in the Firecracker VM with Helios state management
func (hf *HeliosFirecrackerSandbox) Execute(ctx context.Context, req ExecutionRequest) (*ExecutionResult, error) {
	hf.mu.Lock()
	defer hf.mu.Unlock()

	if hf.state != StateReady {
		return nil, fmt.Errorf("sandbox %s is not ready (state: %s)", hf.id, hf.state)
	}

	hf.state = StateRunning
	hf.lastUsedAt = time.Now()

	defer func() {
		hf.state = StateReady
	}()

	// Execute command in Firecracker VM
	result, err := hf.firecrackerVM.Execute(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("failed to execute command in Firecracker VM: %w", err)
	}

	hf.logger.WithFields(logrus.Fields{
		"command":   req.Command,
		"exit_code": result.ExitCode,
		"duration":  result.Duration,
	}).Debug("Command executed in integrated sandbox")

	return result, nil
}

// CreateSnapshot creates both VM and Helios snapshots
func (hf *HeliosFirecrackerSandbox) CreateSnapshot(ctx context.Context, snapshotID string) error {
	hf.mu.Lock()
	defer hf.mu.Unlock()

	if hf.state != StateReady {
		return fmt.Errorf("sandbox %s is not ready for snapshot (state: %s)", hf.id, hf.state)
	}

	startTime := time.Now()
	hf.state = StateSnapshot

	defer func() {
		hf.state = StateReady
	}()

	// Create Helios snapshot first (captures file system state)
	heliosSnapshotID, metrics, err := hf.heliosManager.CreateSnapshot(ctx, fmt.Sprintf("snapshot-%s", snapshotID))
	if err != nil {
		hf.logger.WithError(err).Warn("Failed to create Helios snapshot - continuing with VM snapshot only")
	} else {
		hf.logger.WithFields(logrus.Fields{
			"snapshot_id":    snapshotID,
			"helios_id":      heliosSnapshotID,
			"helios_commit_time": metrics.CommitTime,
		}).Debug("Helios snapshot created")
	}

	// Create Firecracker VM snapshot (captures memory state)
	if err := hf.firecrackerVM.CreateSnapshot(ctx, snapshotID); err != nil {
		return fmt.Errorf("failed to create Firecracker snapshot: %w", err)
	}

	totalTime := time.Since(startTime)
	hf.logger.WithFields(logrus.Fields{
		"snapshot_id": snapshotID,
		"total_time":  totalTime,
	}).Info("Integrated snapshot created successfully")

	return nil
}

// RestoreSnapshot restores both VM and Helios state
func (hf *HeliosFirecrackerSandbox) RestoreSnapshot(ctx context.Context, snapshotID string) error {
	hf.mu.Lock()
	defer hf.mu.Unlock()

	startTime := time.Now()
	hf.state = StateSnapshot

	defer func() {
		hf.state = StateReady
	}()

	// Restore Firecracker VM snapshot first (memory state)
	if err := hf.firecrackerVM.RestoreSnapshot(ctx, snapshotID); err != nil {
		return fmt.Errorf("failed to restore Firecracker snapshot: %w", err)
	}

	// Then restore Helios state (file system state)  
	heliosSnapshotID := fmt.Sprintf("snapshot-%s", snapshotID)
	if _, err := hf.heliosManager.RestoreSnapshot(ctx, heliosSnapshotID); err != nil {
		hf.logger.WithError(err).Warn("Failed to restore Helios snapshot - VM state restored but filesystem may be inconsistent")
	} else {
		hf.logger.WithField("helios_id", heliosSnapshotID).Debug("Helios snapshot restored")
	}

	totalTime := time.Since(startTime)
	hf.logger.WithFields(logrus.Fields{
		"snapshot_id": snapshotID,
		"total_time":  totalTime,
	}).Info("Integrated snapshot restored successfully")

	return nil
}

// ListSnapshots returns available snapshots
func (hf *HeliosFirecrackerSandbox) ListSnapshots(ctx context.Context) ([]string, error) {
	hf.mu.RLock()
	defer hf.mu.RUnlock()

	// Get snapshots from Firecracker (primary source)
	return hf.firecrackerVM.ListSnapshots(ctx)
}

// GetInfo returns sandbox information
func (hf *HeliosFirecrackerSandbox) GetInfo(ctx context.Context) (*SandboxInfo, error) {
	hf.mu.RLock()
	defer hf.mu.RUnlock()

	// Get base info from Firecracker VM
	vmInfo, err := hf.firecrackerVM.GetInfo(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get Firecracker VM info: %w", err)
	}

	// Enhance with integrated sandbox info
	info := &SandboxInfo{
		ID:          hf.id,
		State:       hf.state,
		Config:      vmInfo.Config,
		Metrics:     vmInfo.Metrics,
		CreatedAt:   hf.createdAt,
		LastUsedAt:  hf.lastUsedAt,
		SnapshotIDs: vmInfo.SnapshotIDs,
	}

	return info, nil
}

// Stop gracefully stops both VM and Helios
func (hf *HeliosFirecrackerSandbox) Stop(ctx context.Context) error {
	hf.mu.Lock()
	defer hf.mu.Unlock()

	// Stop Firecracker VM
	if err := hf.firecrackerVM.Stop(ctx); err != nil {
		hf.logger.WithError(err).Warn("Failed to stop Firecracker VM")
	}

	// Close Helios manager
	if err := hf.heliosManager.Close(); err != nil {
		hf.logger.WithError(err).Warn("Failed to close Helios manager")
	}

	hf.state = StateStopped
	hf.logger.Info("Integrated sandbox stopped")

	return nil
}

// Destroy permanently destroys both VM and Helios state
func (hf *HeliosFirecrackerSandbox) Destroy(ctx context.Context) error {
	hf.mu.Lock()
	defer hf.mu.Unlock()

	// Destroy Firecracker VM
	if err := hf.firecrackerVM.Destroy(ctx); err != nil {
		hf.logger.WithError(err).Warn("Failed to destroy Firecracker VM")
	}

	// Close Helios manager
	if err := hf.heliosManager.Close(); err != nil {
		hf.logger.WithError(err).Warn("Failed to close Helios manager")
	}

	// Clean up work directory
	if err := os.RemoveAll(hf.workDir); err != nil {
		hf.logger.WithError(err).Warn("Failed to remove work directory")
	}

	hf.state = StateDestroyed
	hf.logger.Info("Integrated sandbox destroyed")

	return nil
}

// GetHeliosManager returns the Helios manager for direct access
func (hf *HeliosFirecrackerSandbox) GetHeliosManager() *HeliosManager {
	return hf.heliosManager
}

// GetFirecrackerVM returns the Firecracker VM for direct access
func (hf *HeliosFirecrackerSandbox) GetFirecrackerVM() *FirecrackerSandbox {
	return hf.firecrackerVM
}

// GetWorkDir returns the working directory
func (hf *HeliosFirecrackerSandbox) GetWorkDir() string {
	return hf.workDir
}

// PerformMCTSIteration demonstrates a complete MCTS iteration cycle
func (hf *HeliosFirecrackerSandbox) PerformMCTSIteration(ctx context.Context, actions []ExecutionRequest) (*MCTSIterationResult, error) {
	hf.logger.Info("Starting MCTS iteration cycle")
	startTime := time.Now()

	// Create initial snapshot using UUID
	initialSnapshotUUID := uuid.New().String()
	initialSnapshot := fmt.Sprintf("mcts-initial-%s", initialSnapshotUUID)
	if err := hf.CreateSnapshot(ctx, initialSnapshot); err != nil {
		return nil, fmt.Errorf("failed to create initial snapshot: %w", err)
	}

	results := make([]*ExecutionResult, 0, len(actions))

	// Execute each action and capture results
	for i, action := range actions {
		actionSnapshotUUID := uuid.New().String()
		actionSnapshot := fmt.Sprintf("mcts-action-%d-%s", i, actionSnapshotUUID)
		
		// Execute action
		result, err := hf.Execute(ctx, action)
		if err != nil {
			return nil, fmt.Errorf("failed to execute action %d: %w", i, err)
		}
		results = append(results, result)

		// Create snapshot after action
		if err := hf.CreateSnapshot(ctx, actionSnapshot); err != nil {
			hf.logger.WithError(err).Warn("Failed to create action snapshot")
		}
	}

	// Restore to initial state for next iteration
	if err := hf.RestoreSnapshot(ctx, initialSnapshot); err != nil {
		return nil, fmt.Errorf("failed to restore initial state: %w", err)
	}

	totalTime := time.Since(startTime)

	mctsResult := &MCTSIterationResult{
		Actions:      actions,
		Results:      results,
		TotalTime:    totalTime,
		SnapshotTime: totalTime / time.Duration(len(actions)+2), // Rough estimate
		RestoreTime:  totalTime / time.Duration(len(actions)+2), // Rough estimate
		Success:      true,
	}

	hf.logger.WithFields(logrus.Fields{
		"total_time":    totalTime,
		"actions_count": len(actions),
		"avg_per_action": totalTime / time.Duration(len(actions)),
	}).Info("MCTS iteration completed")

	return mctsResult, nil
}

// MCTSIterationResult contains results from an MCTS iteration cycle
type MCTSIterationResult struct {
	Actions      []ExecutionRequest `json:"actions"`
	Results      []*ExecutionResult `json:"results"`
	TotalTime    time.Duration      `json:"total_time"`
	SnapshotTime time.Duration      `json:"snapshot_time"`
	RestoreTime  time.Duration      `json:"restore_time"`
	Success      bool               `json:"success"`
}