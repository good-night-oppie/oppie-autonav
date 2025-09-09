// SPDX-FileCopyrightText: 2024 EdwardTang
// SPDX-License-Identifier: MIT

package sandbox

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/sirupsen/logrus"
)

// HeliosManager manages Helios state operations within VMs
type HeliosManager struct {
	workDir    string
	binaryPath string
	logger     *logrus.Logger
}

// HeliosConfig defines configuration for Helios integration
type HeliosConfig struct {
	WorkDir    string `json:"work_dir"`    // Working directory for Helios operations
	BinaryPath string `json:"binary_path"` // Path to helios-cli binary
}

// SnapshotMetrics contains performance metrics for snapshot operations
type SnapshotMetrics struct {
	CommitTime     time.Duration `json:"commit_time"`
	RestoreTime    time.Duration `json:"restore_time"`
	ObjectCount    int           `json:"object_count"`
	DedupRatio     float64       `json:"dedup_ratio"`
	StorageSize    int64         `json:"storage_size"`
	OperationTime  time.Time     `json:"operation_time"`
}

// NewHeliosManager creates a new Helios manager instance
func NewHeliosManager(config HeliosConfig) (*HeliosManager, error) {
	if config.BinaryPath == "" {
		return nil, fmt.Errorf("binary_path is required")
	}
	
	if config.WorkDir == "" {
		return nil, fmt.Errorf("work_dir is required")
	}

	// Check if binary exists and is executable
	if _, err := os.Stat(config.BinaryPath); os.IsNotExist(err) {
		return nil, fmt.Errorf("helios-cli binary not found at %s", config.BinaryPath)
	}

	// Convert binary path to absolute path
	binaryPath, err := filepath.Abs(config.BinaryPath)
	if err != nil {
		return nil, fmt.Errorf("failed to get absolute binary path: %w", err)
	}

	// Ensure work directory exists
	if err := os.MkdirAll(config.WorkDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create work directory: %w", err)
	}

	hm := &HeliosManager{
		workDir:    config.WorkDir,
		binaryPath: binaryPath,
		logger:     logrus.New(),
	}

	return hm, nil
}

// Initialize initializes the Helios storage in the work directory
func (hm *HeliosManager) Initialize(ctx context.Context) error {
	cmd := exec.CommandContext(ctx, hm.binaryPath, "init", "--work", hm.workDir)
	
	hm.logger.WithFields(logrus.Fields{
		"command": cmd.String(),
		"work_dir": hm.workDir,
	}).Debug("Initializing Helios storage")

	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("helios init failed: %w, output: %s", err, string(output))
	}

	hm.logger.Info("Helios storage initialized")
	return nil
}

// Commit creates a snapshot of the current state
func (hm *HeliosManager) Commit(ctx context.Context, message string) (string, *SnapshotMetrics, error) {
	startTime := time.Now()
	
	cmd := exec.CommandContext(ctx, hm.binaryPath, "commit", "--work", hm.workDir, "--message", message)
	
	hm.logger.WithFields(logrus.Fields{
		"command": cmd.String(),
		"work_dir": hm.workDir,
		"message": message,
	}).Debug("Executing Helios commit")

	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", nil, fmt.Errorf("helios commit failed: %w, output: %s", err, string(output))
	}

	commitTime := time.Since(startTime)
	
	// Parse snapshot ID from JSON output
	outputStr := strings.TrimSpace(string(output))
	if outputStr == "" {
		return "", nil, fmt.Errorf("empty output returned")
	}
	
	// Extract actual snapshot ID from JSON response
	var snapshotResponse struct {
		SnapshotID string `json:"snapshot_id"`
	}
	
	if err := json.Unmarshal([]byte(outputStr), &snapshotResponse); err != nil {
		return "", nil, fmt.Errorf("failed to parse snapshot response: %w", err)
	}
	
	if snapshotResponse.SnapshotID == "" {
		return "", nil, fmt.Errorf("empty snapshot ID in response")
	}
	
	snapshotID := snapshotResponse.SnapshotID

	metrics := &SnapshotMetrics{
		CommitTime:    commitTime,
		OperationTime: startTime,
	}

	hm.logger.WithFields(logrus.Fields{
		"snapshot_id": snapshotID,
		"commit_time": commitTime,
	}).Info("Helios commit completed")

	return snapshotID, metrics, nil
}

// CreateSnapshot is an alias for Commit for consistency with Sandbox interface
func (hm *HeliosManager) CreateSnapshot(ctx context.Context, message string) (string, *SnapshotMetrics, error) {
	return hm.Commit(ctx, message)
}

// RestoreSnapshot restores state from a snapshot
func (hm *HeliosManager) RestoreSnapshot(ctx context.Context, snapshotID string) (*SnapshotMetrics, error) {
	if snapshotID == "" {
		return nil, fmt.Errorf("snapshot ID cannot be empty")
	}

	startTime := time.Now()
	
	cmd := exec.CommandContext(ctx, hm.binaryPath, "restore", "--work", hm.workDir, "--id", snapshotID)
	
	hm.logger.WithFields(logrus.Fields{
		"command": cmd.String(),
		"snapshot_id": snapshotID,
	}).Debug("Executing Helios restore")

	output, err := cmd.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("helios restore failed: %w, output: %s", err, string(output))
	}

	restoreTime := time.Since(startTime)
	
	metrics := &SnapshotMetrics{
		RestoreTime:   restoreTime,
		OperationTime: startTime,
	}

	hm.logger.WithFields(logrus.Fields{
		"snapshot_id": snapshotID,
		"restore_time": restoreTime,
	}).Info("Helios restore completed")

	return metrics, nil
}

// Stats retrieves statistics about the Helios storage
func (hm *HeliosManager) Stats(ctx context.Context) (string, error) {
	cmd := exec.CommandContext(ctx, hm.binaryPath, "stats", "--work", hm.workDir)
	
	hm.logger.WithField("command", cmd.String()).Debug("Executing Helios stats")

	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("helios stats failed: %w, output: %s", err, string(output))
	}

	return string(output), nil
}

// Close performs any necessary cleanup
func (hm *HeliosManager) Close() error {
	hm.logger.Info("Helios manager closed")
	return nil
}

// GetWorkDir returns the working directory path
func (hm *HeliosManager) GetWorkDir() string {
	return hm.workDir
}

// GetBinaryPath returns the helios-cli binary path
func (hm *HeliosManager) GetBinaryPath() string {
	return hm.binaryPath
}

// DefaultHeliosConfig returns a default Helios configuration
func DefaultHeliosConfig() HeliosConfig {
	return HeliosConfig{
		WorkDir:    "/tmp/helios",
		BinaryPath: "./bin/helios-cli",
	}
}