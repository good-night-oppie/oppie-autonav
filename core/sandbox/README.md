# Hot-Loop Sandbox Package

This package provides high-performance, memory-level virtualization for MCTS exploration with sub-second iteration times using Firecracker microVMs.

## Architecture Overview

The sandbox system is built around three core components:

- **Sandbox**: Individual microVM instances with snapshot capabilities
- **SandboxPool**: Pool management for pre-warmed VMs and resource optimization
- **SandboxManager**: High-level orchestration and lifecycle management

## Key Features

### Performance Targets
- VM Startup: <100ms (P95), <150ms (P99)
- Snapshot Restore: <50ms (P95), <75ms (P99)
- Concurrent VMs: 100+ simultaneous executions
- Memory Efficiency: <10MB overhead per idle VM

### Capabilities
- **Firecracker Integration**: Native microVM management via firecracker-go-sdk
- **VM Pool Management**: Pre-warmed VMs for instant availability
- **Snapshot Support**: Fast state persistence and restoration
- **Resource Isolation**: Hardware-level VM isolation with configurable limits
- **Hot-State Management**: Zero-cost state transitions for MCTS backtracking
- **Concurrent Execution**: Thread-safe operations with comprehensive metrics

## Quick Start

### Basic Usage

```go
package main

import (
    "context"
    "fmt"
    "time"
    
    "github.com/good-night-oppie/oppie-autonav/core/sandbox"
)

func main() {
    ctx := context.Background()
    
    // Configure sandbox template
    template := sandbox.SandboxConfig{
        MemoryMB:        512,
        CPUCount:        1,
        TimeoutSeconds:  30,
        EnableNetwork:   true,
        KernelImagePath: "/path/to/kernel.bin",
        RootFSPath:      "/path/to/rootfs.ext4",
    }
    
    // Create sandbox manager with pool of 10 VMs
    manager := sandbox.NewSandboxManager(10, template)
    defer manager.Shutdown(ctx)
    
    // Create sandbox
    config := sandbox.SandboxConfig{VMID: "my-sandbox"}
    sb, err := manager.CreateSandbox(ctx, config)
    if err != nil {
        panic(err)
    }
    
    // Execute command
    req := sandbox.ExecutionRequest{
        Command: []string{"echo", "Hello World"},
        Timeout: 10 * time.Second,
    }
    
    result, err := sb.Execute(ctx, req)
    if err != nil {
        panic(err)
    }
    
    fmt.Printf("Output: %s\n", result.Stdout)
    fmt.Printf("Duration: %v\n", result.Duration)
    
    // Create snapshot
    err = sb.CreateSnapshot(ctx, "checkpoint1")
    if err != nil {
        panic(err)
    }
    
    // Release back to pool
    err = manager.ReleaseSandbox(ctx, sb)
    if err != nil {
        panic(err)
    }
}
```

### MCTS Integration Example

```go
// MCTS node execution with sandbox
func (m *MCTSSandbox) ExecuteNode(node *MCTSNode) (*ExecutionResult, error) {
    ctx := context.Background()
    
    // Acquire sandbox from pool
    sandbox, err := m.pool.Acquire(ctx, m.config)
    if err != nil {
        return nil, err
    }
    defer m.pool.Release(ctx, sandbox)
    
    // Restore to parent state if needed
    if node.ParentSnapshotID != "" {
        err = sandbox.RestoreSnapshot(ctx, node.ParentSnapshotID)
        if err != nil {
            return nil, err
        }
    }
    
    // Execute node action
    req := sandbox.ExecutionRequest{
        Command: node.Action.Command,
        WorkDir: node.Action.WorkDir,
        Timeout: 30 * time.Second,
    }
    
    result, err := sandbox.Execute(ctx, req)
    if err != nil {
        return nil, err
    }
    
    // Create snapshot for child nodes
    snapshotID := fmt.Sprintf("node-%s", node.ID)
    err = sandbox.CreateSnapshot(ctx, snapshotID)
    if err != nil {
        return nil, err
    }
    
    node.SnapshotID = snapshotID
    return result, nil
}
```

## Configuration

### Sandbox Configuration

```go
config := sandbox.SandboxConfig{
    // Resource limits
    MemoryMB:       512,        // VM memory in MB
    CPUCount:       1,          // Number of vCPUs
    DiskSizeMB:     1024,       // Root disk size in MB
    TimeoutSeconds: 30,         // Default execution timeout
    
    // Network settings
    EnableNetwork:  true,       // Enable network access
    NetworkMode:    "bridge",   // Network mode: bridge, none, host
    
    // Firecracker paths
    KernelImagePath: "/path/to/kernel.bin",
    RootFSPath:      "/path/to/rootfs.ext4",
    SocketPath:      "/tmp/fc.sock",  // Optional, auto-generated if empty
    
    // Identification
    VMID:       "my-vm-123",    // Unique VM identifier
    SnapshotID: "base-state",   // Optional initial snapshot
}
```

### Pool Configuration

```go
// Create manager with custom pool size
manager := sandbox.NewSandboxManager(poolSize, template)

// Pool automatically maintains 25% pre-warmed VMs
// Performs cleanup every 30 seconds
// Destroys unused VMs after 5 minutes
```

## Performance Benchmarks

Run comprehensive benchmarks:

```bash
go test -bench=. -benchmem -benchtime=10s
```

### Key Benchmarks

- `BenchmarkVMStartup`: VM creation time (target: <100ms)
- `BenchmarkSnapshotRestore`: Snapshot operations (target: <50ms)  
- `BenchmarkConcurrentVMs`: Parallel execution scaling
- `BenchmarkThroughput`: Operations per second
- `BenchmarkResourceContention`: Behavior under load

Example results:
```
BenchmarkVMStartup-8         	   20000	     87234 ns/op
BenchmarkSnapshotRestore-8   	   50000	     31245 ns/op
BenchmarkConcurrentVMs-8     	  100000	     12456 ns/op
```

## Testing

### Run Tests

```bash
# All tests
go test ./...

# Specific test suites
go test -run TestSandbox ./...
go test -run TestPool ./...
go test -run TestManager ./...

# With coverage
go test -cover ./...

# Race detection
go test -race ./...
```

### Test Structure

- `sandbox_test.go`: Core sandbox interface tests
- `pool_test.go`: Pool management and concurrency tests  
- `manager_test.go`: High-level orchestration tests
- `benchmark_test.go`: Performance validation tests

All tests use mock implementations for unit testing. Integration tests with real Firecracker VMs are in separate files.

## Monitoring & Metrics

### Sandbox Metrics

```go
// Get individual sandbox metrics
info, err := sandbox.GetInfo(ctx)
metrics := info.Metrics

fmt.Printf("Startup Time: %v\n", metrics.VMStartupTime)
fmt.Printf("Memory Used: %d bytes\n", metrics.TotalMemoryUsed)
fmt.Printf("CPU Usage: %.2f%%\n", metrics.CPUUtilization)
```

### Pool Statistics

```go
// Get pool utilization
stats, err := pool.GetPoolStats(ctx)

fmt.Printf("Pool Utilization: %.2f%%\n", stats.PoolUtilization)
fmt.Printf("Available VMs: %d\n", stats.AvailableCount)
fmt.Printf("Average Startup: %v\n", stats.AverageStartupTime)
```

### Manager Statistics  

```go
// Get comprehensive stats
stats, err := manager.GetSandboxStats(ctx)

fmt.Printf("Total Sandboxes: %d\n", stats.TotalSandboxes)
fmt.Printf("Success Rate: %.2f%%\n", stats.SuccessRate)
fmt.Printf("Ops/sec: %.1f\n", stats.TotalExecutions)
```

## Error Handling

The package provides structured error handling with context:

```go
result, err := sandbox.Execute(ctx, req)
if err != nil {
    switch {
    case errors.Is(err, context.DeadlineExceeded):
        // Handle timeout
    case errors.Is(err, sandbox.ErrSandboxDestroyed):
        // Handle destroyed sandbox
    case errors.Is(err, sandbox.ErrPoolExhausted):
        // Handle pool capacity
    default:
        // Handle other errors
    }
}
```

## Resource Management

### Automatic Cleanup

The sandbox system automatically:
- Removes unused VMs after 5 minutes of inactivity
- Performs health checks every 30 seconds
- Cleans up crashed or corrupted VMs
- Manages socket files and temporary resources

### Manual Cleanup

```go
// Health check and cleanup
err := manager.HealthCheck(ctx)
if err != nil {
    log.Printf("Cleaned up %v unhealthy sandboxes", err)
}

// Force cleanup
err = pool.Cleanup(ctx)

// Graceful shutdown
err = manager.Shutdown(ctx)
```

## Security Considerations

### VM Isolation
- Hardware-level isolation via Firecracker
- Configurable memory and CPU limits
- Network isolation options
- File system sandboxing

### Resource Limits
```go
config := sandbox.SandboxConfig{
    MemoryMB:   256,    // Limit VM memory
    CPUCount:   1,      // Limit CPU cores  
    DiskSizeMB: 512,    // Limit disk space
    TimeoutSeconds: 30, // Execution timeout
}
```

### Best Practices
- Use minimal rootfs images
- Enable network isolation when not needed
- Set appropriate resource limits
- Regular security updates for kernel/rootfs

## Troubleshooting

### Common Issues

**VM Startup Failures**
```bash
# Check Firecracker binary
which firecracker

# Verify kernel/rootfs paths
ls -la /path/to/kernel.bin /path/to/rootfs.ext4

# Check socket permissions
ls -la /tmp/firecracker-*.sock
```

**Performance Issues**
```bash
# Run benchmarks
go test -bench=BenchmarkVMStartup -benchtime=30s

# Check resource usage
top -p $(pgrep firecracker)

# Monitor pool stats
curl localhost:8080/metrics  # If metrics endpoint enabled
```

**Memory Leaks**
```bash
# Memory profiling
go test -memprofile=mem.prof -bench=.
go tool pprof mem.prof

# Check for VM cleanup
ps aux | grep firecracker
```

### Debug Logging

```go
import "github.com/sirupsen/logrus"

// Enable debug logging
logrus.SetLevel(logrus.DebugLevel)

// Or use structured logging
logger := logrus.WithFields(logrus.Fields{
    "component": "sandbox",
    "vm_id":     "debug-vm",
})
```

## Contributing

1. Follow Go best practices and existing code style
2. Add comprehensive tests for new features
3. Update benchmarks for performance-critical changes
4. Document public APIs with godoc comments
5. Ensure all tests pass: `go test -race ./...`

## Dependencies

- [firecracker-go-sdk](https://github.com/firecracker-microvm/firecracker-go-sdk): Firecracker integration
- [logrus](https://github.com/sirupsen/logrus): Structured logging
- [testify](https://github.com/stretchr/testify): Testing utilities
- [uuid](https://github.com/google/uuid): UUID generation

## License

SPDX-License-Identifier: MIT