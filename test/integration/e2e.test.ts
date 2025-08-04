// tests/integration/e2e.test.ts
import {
  describe,
  it,
  expect,
  vi,
  beforeEach,
  afterEach,
  beforeAll,
} from "vitest";
import { FabstirSDK } from "../../src/index";
import { ethers } from "ethers";
import type {
  JobSubmissionResult,
  JobStatus,
  P2PResponseStream,
  PerformanceMetrics,
  ModeTransitionReport,
} from "../../src/types";

// Mock all components for integration testing
vi.mock("../../src/p2p/client", () => ({
  P2PClient: vi.fn().mockImplementation(() => {
    let isStarted = false;
    let connectionCount = 0;

    return {
      start: vi.fn().mockImplementation(async () => {
        await new Promise((resolve) => setTimeout(resolve, 100)); // Simulate connection time
        isStarted = true;
        connectionCount = 3; // Simulate 3 peer connections
      }),
      stop: vi.fn().mockImplementation(async () => {
        isStarted = false;
        connectionCount = 0;
      }),
      isStarted: vi.fn().mockImplementation(() => isStarted),
      getP2PMetrics: vi.fn().mockImplementation(() => ({
        totalPeers: 5,
        connectedPeers: ["peer1", "peer2", "peer3"],
        listenAddresses: ["/ip4/127.0.0.1/tcp/4001"],
        uptime: 12345,
        failedConnections: 2,
        successfulConnections: 3,
      })),
      findProviders: vi.fn().mockResolvedValue([
        {
          peerId: "12D3KooWNode1",
          multiaddrs: ["/ip4/192.168.1.1/tcp/4001/p2p/12D3KooWNode1"],
          capabilities: {
            models: ["llama-3.2-1b-instruct", "llama-3.2-3b-instruct"],
            maxTokens: 4096,
            pricePerToken: "1000000",
          },
          latency: 45,
          reputation: 95,
          lastSeen: Date.now(),
        },
        {
          peerId: "12D3KooWNode2",
          multiaddrs: ["/ip4/192.168.1.2/tcp/4001/p2p/12D3KooWNode2"],
          capabilities: {
            models: ["llama-3.2-1b-instruct"],
            maxTokens: 2048,
            pricePerToken: "1200000",
          },
          latency: 60,
          reputation: 88,
          lastSeen: Date.now(),
        },
      ]),
      sendJobRequest: vi.fn().mockImplementation(async (nodeId, request) => {
        // Simulate processing time
        await new Promise((resolve) => setTimeout(resolve, 50));

        return {
          requestId: request.id,
          nodeId,
          status: "accepted",
          actualCost: ethers.BigNumber.from("95000000"),
          estimatedTime: 2000,
        };
      }),
      createResponseStream: vi.fn().mockImplementation((nodeId, options) => {
        const stream = new MockP2PResponseStream(options.jobId, nodeId);
        setTimeout(() => stream.startStreaming(), 100);
        return stream;
      }),
      on: vi.fn(),
      submitJob: vi.fn().mockResolvedValue("p2p-job-123"),
    };
  }),
}));

// Mock response stream for testing
class MockP2PResponseStream {
  jobId: string;
  nodeId: string;
  status: "active" | "paused" | "closed" | "error" = "active";
  startTime: number = Date.now();
  bytesReceived: number = 0;
  tokensReceived: number = 0;
  private listeners: Map<string, Function[]> = new Map();
  private streamInterval?: NodeJS.Timeout;

  constructor(jobId: string, nodeId: string) {
    this.jobId = jobId;
    this.nodeId = nodeId;
  }

  on(event: string, listener: Function): void {
    if (!this.listeners.has(event)) {
      this.listeners.set(event, []);
    }
    this.listeners.get(event)!.push(listener);
  }

  emit(event: string, data: any): void {
    const eventListeners = this.listeners.get(event) || [];
    eventListeners.forEach((listener) => listener(data));
  }

  startStreaming(): void {
    const tokens = [
      "Hello",
      " ",
      "from",
      " ",
      "the",
      " ",
      "decentralized",
      " ",
      "AI",
      " ",
      "network",
      "!",
    ];
    let index = 0;

    this.streamInterval = setInterval(() => {
      if (index < tokens.length) {
        this.tokensReceived++;
        this.bytesReceived += tokens[index].length;
        this.emit("token", {
          content: tokens[index],
          index: this.tokensReceived,
          timestamp: Date.now(),
        });
        index++;
      } else {
        this.close();
        this.emit("end", {
          totalTokens: this.tokensReceived,
          duration: Date.now() - this.startTime,
          finalStatus: "completed",
        });
      }
    }, 100);
  }

  pause(): void {
    this.status = "paused";
    if (this.streamInterval) {
      clearInterval(this.streamInterval);
    }
  }

  resume(): void {
    this.status = "active";
    // In real implementation, would resume from last position
  }

  close(): void {
    this.status = "closed";
    if (this.streamInterval) {
      clearInterval(this.streamInterval);
      this.streamInterval = undefined;
    }
  }

  getMetrics(): any {
    return {
      tokensReceived: this.tokensReceived,
      bytesReceived: this.bytesReceived,
      tokensPerSecond:
        this.tokensReceived / ((Date.now() - this.startTime) / 1000),
      averageLatency: 100,
      startTime: this.startTime,
    };
  }
}

describe("Integration Testing - Sub-phase 2.11", () => {
  let sdk: FabstirSDK;
  let mockProvider: any;
  let performanceMetrics: PerformanceMetrics;

  beforeAll(() => {
    // Initialize performance metrics
    performanceMetrics = {
      startTime: Date.now(),
      operations: [],
    };
  });

  beforeEach(() => {
    // Reset SDK instance
    sdk = null as any;

    // Mock provider
    mockProvider = {
      getNetwork: vi.fn().mockResolvedValue({ chainId: 84532 }),
      getSigner: vi.fn().mockReturnValue({
        getAddress: vi
          .fn()
          .mockResolvedValue("0x742d35Cc6634C0532925a3b844Bc9e7595f5b9A1"),
        signMessage: vi.fn().mockResolvedValue("0xsignature"),
      }),
      on: vi.fn(),
      removeListener: vi.fn(),
      getBlock: vi.fn().mockResolvedValue({ timestamp: Date.now() / 1000 }),
    };
  });

  afterEach(async () => {
    if (sdk && sdk.isConnected) {
      await sdk.disconnect();
    }
    vi.clearAllMocks();
  });

  describe("Full Job Lifecycle", () => {
    it("should complete entire job flow from submission to result", async () => {
      // Track lifecycle events
      const lifecycleEvents: string[] = [];

      // Initialize SDK in production mode
      sdk = new FabstirSDK({
        mode: "production",
        p2pConfig: {
          bootstrapNodes: ["/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWBootstrap"],
        },
      });

      // Connect and verify
      const connectStart = Date.now();
      await sdk.connect(mockProvider);
      const connectTime = Date.now() - connectStart;

      expect(sdk.isConnected).toBe(true);
      expect(sdk.getStatus().mode).toBe("production");
      lifecycleEvents.push("connected");

      // Discover nodes
      const discoveryStart = Date.now();
      const nodes = await sdk.discoverNodes({
        modelId: "llama-3.2-1b-instruct",
      });
      const discoveryTime = Date.now() - discoveryStart;

      expect(nodes.length).toBeGreaterThan(0);
      lifecycleEvents.push("discovered_nodes");

      // Submit job with negotiation
      const submissionStart = Date.now();
      const result = await sdk.submitJobWithNegotiation({
        prompt: "What is the meaning of life?",
        modelId: "llama-3.2-1b-instruct",
        maxTokens: 100,
      });
      const submissionTime = Date.now() - submissionStart;

      expect(result.jobId).toBeTruthy();
      expect(result.selectedNode).toBeTruthy();
      lifecycleEvents.push("job_submitted");

      // Get response stream
      const streamStart = Date.now();
      const stream = await sdk.createResponseStream({
        jobId: result.jobId,
        requestId: `req-${result.jobId}`,
      });

      expect(stream).toBeTruthy();
      lifecycleEvents.push("stream_created");

      // Collect tokens
      const tokens: string[] = [];
      await new Promise<void>((resolve) => {
        stream.on("token", (token: any) => {
          tokens.push(token.content);
        });

        stream.on("end", (summary: any) => {
          const streamTime = Date.now() - streamStart;
          lifecycleEvents.push("stream_completed");

          // Record performance metrics
          performanceMetrics.operations.push({
            operation: "full_job_lifecycle",
            connectTime,
            discoveryTime,
            submissionTime,
            streamTime,
            totalTime: Date.now() - connectStart,
            tokensReceived: summary.totalTokens,
          });

          resolve();
        });
      });

      // Verify complete lifecycle
      expect(tokens.length).toBeGreaterThan(0);
      expect(lifecycleEvents).toEqual([
        "connected",
        "discovered_nodes",
        "job_submitted",
        "stream_created",
        "stream_completed",
      ]);

      // Check job status
      const status = await sdk.getJobStatus(result.jobId);
      expect(status.status).toBe(JobStatus.COMPLETED);
    });

    it("should handle job lifecycle with contract integration", async () => {
      sdk = new FabstirSDK({
        mode: "production",
        p2pConfig: {
          bootstrapNodes: ["/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWBootstrap"],
        },
      });

      await sdk.connect(mockProvider);

      // Mock contract for this test
      const mockContract = {
        postJob: vi.fn().mockResolvedValue({
          wait: vi.fn().mockResolvedValue({
            events: [
              {
                event: "JobPosted",
                args: [ethers.BigNumber.from(1001)],
              },
            ],
            transactionHash: "0x123abc",
          }),
          hash: "0x123abc",
        }),
        on: vi.fn(),
        removeListener: vi.fn(),
      };

      // Set up contract
      sdk.contracts = { jobMarketplace: mockContract } as any;

      // Submit with blockchain integration
      const result = await sdk.submitJobWithNegotiation({
        prompt: "Blockchain integrated job",
        modelId: "llama-3.2-1b-instruct",
        maxTokens: 50,
        submitToChain: true,
      });

      expect(result.txHash).toBeTruthy();
      expect(result.jobId).toBe(1001);
      expect(mockContract.postJob).toHaveBeenCalled();

      // Verify job mapping exists
      const mapping = await sdk.getJobMapping(result.jobId);
      expect(mapping).toBeTruthy();
      expect(mapping?.blockchainJobId).toBe(1001);
    });
  });

  describe("Mode Switching", () => {
    it("should seamlessly switch between mock and production modes", async () => {
      const modeTransitions: ModeTransitionReport[] = [];

      // Start in mock mode
      sdk = new FabstirSDK({
        mode: "mock",
      });

      await sdk.connect(mockProvider);
      expect(sdk.getStatus().mode).toBe("mock");

      // Submit job in mock mode
      const mockStart = Date.now();
      const mockResult = await sdk.submitJob({
        prompt: "Test in mock mode",
        modelId: "llama-3.2-1b-instruct",
        maxTokens: 50,
      });
      const mockTime = Date.now() - mockStart;

      expect(mockResult).toBeTruthy();
      modeTransitions.push({
        fromMode: "mock",
        toMode: "mock",
        operation: "submitJob",
        duration: mockTime,
        success: true,
      });

      // Disconnect
      await sdk.disconnect();

      // Reconnect in production mode
      sdk = new FabstirSDK({
        mode: "production",
        p2pConfig: {
          bootstrapNodes: ["/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWBootstrap"],
        },
      });

      const prodStart = Date.now();
      await sdk.connect(mockProvider);
      const prodConnectTime = Date.now() - prodStart;

      expect(sdk.getStatus().mode).toBe("production");
      expect(sdk.getStatus().p2pStatus?.connected).toBe(true);

      // Submit job in production mode
      const prodSubmitStart = Date.now();
      const prodResult = await sdk.submitJobWithNegotiation({
        prompt: "Test in production mode",
        modelId: "llama-3.2-1b-instruct",
        maxTokens: 50,
      });
      const prodSubmitTime = Date.now() - prodSubmitStart;

      expect(prodResult.selectedNode).toBeTruthy();
      modeTransitions.push({
        fromMode: "mock",
        toMode: "production",
        operation: "connect",
        duration: prodConnectTime,
        success: true,
      });
      modeTransitions.push({
        fromMode: "production",
        toMode: "production",
        operation: "submitJob",
        duration: prodSubmitTime,
        success: true,
      });

      // Verify behavior differences
      expect(mockTime).toBeLessThan(prodSubmitTime); // Mock should be faster

      // Record mode switching performance
      performanceMetrics.operations.push({
        operation: "mode_switching",
        transitions: modeTransitions,
        totalTransitions: modeTransitions.length,
      });
    });

    it("should maintain state consistency during mode switches", async () => {
      // Start in production mode
      sdk = new FabstirSDK({
        mode: "production",
        p2pConfig: {
          bootstrapNodes: ["/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWBootstrap"],
        },
      });

      await sdk.connect(mockProvider);

      // Submit a job
      const job1 = await sdk.submitJobWithNegotiation({
        prompt: "Job before mode switch",
        modelId: "llama-3.2-1b-instruct",
        maxTokens: 50,
      });

      // Store job ID
      const jobId = job1.jobId;

      // Disconnect and switch to mock mode
      await sdk.disconnect();

      sdk = new FabstirSDK({
        mode: "mock",
      });

      await sdk.connect(mockProvider);

      // Try to get status of production job (should fail gracefully)
      try {
        await sdk.getJobStatus(jobId);
      } catch (error: any) {
        expect(error.message).toContain("Job not found");
      }

      // Submit new job in mock mode
      const mockJob = await sdk.submitJob({
        prompt: "Mock mode job",
        modelId: "llama-3.2-1b-instruct",
        maxTokens: 50,
      });

      expect(mockJob).toBeTruthy();

      // Verify mock job works
      const mockStatus = await sdk.getJobStatus(mockJob);
      expect(mockStatus.status).toBe(JobStatus.PROCESSING);
    });
  });

  describe("Fallback Scenarios", () => {
    it("should fallback to P2P when blockchain fails", async () => {
      sdk = new FabstirSDK({
        mode: "production",
        p2pConfig: {
          bootstrapNodes: ["/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWBootstrap"],
        },
      });

      await sdk.connect(mockProvider);

      // Mock contract failure
      const mockContract = {
        postJob: vi.fn().mockRejectedValue(new Error("Network congestion")),
        on: vi.fn(),
        removeListener: vi.fn(),
      };

      sdk.contracts = { jobMarketplace: mockContract } as any;

      // Submit with blockchain but allow P2P fallback
      const result = await sdk.submitJobWithNegotiation({
        prompt: "Test fallback",
        modelId: "llama-3.2-1b-instruct",
        maxTokens: 50,
        submitToChain: true,
        allowP2PFallback: true,
      });

      // Should succeed via P2P
      expect(result.jobId).toBeTruthy();
      expect(result.p2pOnly).toBe(true);
      expect(result.txHash).toBeUndefined();
    });

    it("should fallback to alternative nodes on node failure", async () => {
      sdk = new FabstirSDK({
        mode: "production",
        p2pConfig: {
          bootstrapNodes: ["/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWBootstrap"],
        },
        failoverStrategy: "automatic",
      });

      await sdk.connect(mockProvider);

      // Track failover events
      const failoverEvents: any[] = [];
      sdk.on("job:failover", (event) => failoverEvents.push(event));

      // Mock first node failing
      let attemptCount = 0;
      sdk._p2pClient.sendJobRequest = vi
        .fn()
        .mockImplementation(async (nodeId) => {
          attemptCount++;
          if (attemptCount === 1 && nodeId === "12D3KooWNode1") {
            throw new Error("Node timeout");
          }
          return {
            requestId: "req-123",
            nodeId,
            status: "accepted",
            actualCost: ethers.BigNumber.from("100000000"),
          };
        });

      // Submit job - should failover to Node2
      const result = await sdk.submitJobWithNegotiation({
        prompt: "Test node failover",
        modelId: "llama-3.2-1b-instruct",
        maxTokens: 50,
      });

      expect(result.selectedNode).toBe("12D3KooWNode2");
      expect(failoverEvents.length).toBe(1);
      expect(failoverEvents[0].originalNode).toBe("12D3KooWNode1");
      expect(failoverEvents[0].newNode).toBe("12D3KooWNode2");
    });

    it("should handle complete P2P network failure gracefully", async () => {
      sdk = new FabstirSDK({
        mode: "production",
        p2pConfig: {
          bootstrapNodes: ["/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWBootstrap"],
        },
      });

      // Mock P2P connection failure
      sdk._p2pClient = {
        start: vi.fn().mockRejectedValue(new Error("No peers available")),
        isStarted: vi.fn().mockReturnValue(false),
      } as any;

      // Should fail to connect
      await expect(sdk.connect(mockProvider)).rejects.toThrow();
      expect(sdk.isConnected).toBe(false);

      // Should provide helpful error for operations
      await expect(
        sdk.discoverNodes({ modelId: "llama-3.2-1b-instruct" })
      ).rejects.toThrow("P2P client not initialized");
    });
  });

  describe("Performance Benchmarks", () => {
    it("should meet performance targets for common operations", async () => {
      sdk = new FabstirSDK({
        mode: "production",
        p2pConfig: {
          bootstrapNodes: ["/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWBootstrap"],
        },
      });

      const benchmarks: any = {
        connect: { target: 500, actual: 0 }, // 500ms target
        discovery: { target: 1000, actual: 0 }, // 1s target
        jobSubmission: { target: 2000, actual: 0 }, // 2s target
        tokenLatency: { target: 200, actual: 0 }, // 200ms per token
      };

      // Benchmark connection
      const connectStart = Date.now();
      await sdk.connect(mockProvider);
      benchmarks.connect.actual = Date.now() - connectStart;

      // Benchmark discovery
      const discoveryStart = Date.now();
      const nodes = await sdk.discoverNodes({
        modelId: "llama-3.2-1b-instruct",
      });
      benchmarks.discovery.actual = Date.now() - discoveryStart;

      // Benchmark job submission
      const submissionStart = Date.now();
      const result = await sdk.submitJobWithNegotiation({
        prompt: "Performance test",
        modelId: "llama-3.2-1b-instruct",
        maxTokens: 50,
      });
      benchmarks.jobSubmission.actual = Date.now() - submissionStart;

      // Benchmark streaming latency
      const stream = await sdk.createResponseStream({
        jobId: result.jobId,
        requestId: `req-${result.jobId}`,
      });

      const tokenTimings: number[] = [];
      let lastTokenTime = Date.now();

      await new Promise<void>((resolve) => {
        stream.on("token", () => {
          const now = Date.now();
          tokenTimings.push(now - lastTokenTime);
          lastTokenTime = now;
        });

        stream.on("end", () => {
          const avgTokenLatency =
            tokenTimings.reduce((a, b) => a + b, 0) / tokenTimings.length;
          benchmarks.tokenLatency.actual = avgTokenLatency;
          resolve();
        });
      });

      // Verify performance meets targets
      expect(benchmarks.connect.actual).toBeLessThan(benchmarks.connect.target);
      expect(benchmarks.discovery.actual).toBeLessThan(
        benchmarks.discovery.target
      );
      expect(benchmarks.jobSubmission.actual).toBeLessThan(
        benchmarks.jobSubmission.target
      );
      expect(benchmarks.tokenLatency.actual).toBeLessThan(
        benchmarks.tokenLatency.target
      );

      // Record benchmark results
      performanceMetrics.operations.push({
        operation: "performance_benchmarks",
        benchmarks,
        allTargetsMet: Object.entries(benchmarks).every(
          ([_, bench]: [string, any]) => bench.actual < bench.target
        ),
      });
    });

    it("should handle high load scenarios efficiently", async () => {
      sdk = new FabstirSDK({
        mode: "production",
        p2pConfig: {
          bootstrapNodes: ["/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWBootstrap"],
        },
      });

      await sdk.connect(mockProvider);

      const concurrentJobs = 10;
      const startTime = Date.now();

      // Submit multiple jobs concurrently
      const jobPromises = Array.from({ length: concurrentJobs }, (_, i) =>
        sdk.submitJobWithNegotiation({
          prompt: `Concurrent job ${i}`,
          modelId: "llama-3.2-1b-instruct",
          maxTokens: 20,
        })
      );

      const results = await Promise.all(jobPromises);
      const totalTime = Date.now() - startTime;
      const avgTimePerJob = totalTime / concurrentJobs;

      // All jobs should succeed
      expect(results.every((r) => r.jobId)).toBe(true);
      expect(results.every((r) => r.selectedNode)).toBe(true);

      // Performance should scale reasonably
      expect(avgTimePerJob).toBeLessThan(500); // 500ms per job average

      performanceMetrics.operations.push({
        operation: "high_load_test",
        concurrentJobs,
        totalTime,
        avgTimePerJob,
        throughput: (concurrentJobs / totalTime) * 1000, // jobs per second
      });
    });

    it("should efficiently cache and reuse discovery results", async () => {
      sdk = new FabstirSDK({
        mode: "production",
        p2pConfig: {
          bootstrapNodes: ["/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWBootstrap"],
        },
        nodeDiscovery: {
          cacheTTL: 5000, // 5 second cache
        },
      });

      await sdk.connect(mockProvider);

      // First discovery (cache miss)
      const discovery1Start = Date.now();
      const nodes1 = await sdk.discoverNodes({
        modelId: "llama-3.2-1b-instruct",
      });
      const discovery1Time = Date.now() - discovery1Start;

      // Second discovery (cache hit)
      const discovery2Start = Date.now();
      const nodes2 = await sdk.discoverNodes({
        modelId: "llama-3.2-1b-instruct",
      });
      const discovery2Time = Date.now() - discovery2Start;

      // Cache hit should be much faster
      expect(discovery2Time).toBeLessThan(discovery1Time / 10);
      expect(nodes1).toEqual(nodes2);

      // Force refresh
      const discovery3Start = Date.now();
      const nodes3 = await sdk.discoverNodes({
        modelId: "llama-3.2-1b-instruct",
        forceRefresh: true,
      });
      const discovery3Time = Date.now() - discovery3Start;

      // Force refresh should take similar time to first discovery
      expect(discovery3Time).toBeGreaterThan(discovery2Time * 5);

      performanceMetrics.operations.push({
        operation: "discovery_caching",
        cacheMissTime: discovery1Time,
        cacheHitTime: discovery2Time,
        forceRefreshTime: discovery3Time,
        cacheEfficiency:
          ((discovery1Time - discovery2Time) / discovery1Time) * 100,
      });
    });
  });

  describe("End-to-End Reliability", () => {
    it("should maintain reliability across node failures and recovery", async () => {
      sdk = new FabstirSDK({
        mode: "production",
        p2pConfig: {
          bootstrapNodes: ["/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWBootstrap"],
        },
        failoverStrategy: "automatic",
        nodeBlacklistDuration: 1000, // 1 second for testing
      });

      await sdk.connect(mockProvider);

      // Simulate node becoming unreliable
      sdk.recordNodeFailure("12D3KooWNode1", "Timeout");
      sdk.recordNodeFailure("12D3KooWNode1", "Timeout");
      sdk.recordNodeFailure("12D3KooWNode1", "Timeout");

      // Node should be blacklisted
      const isBlacklisted = await sdk.isNodeBlacklisted("12D3KooWNode1");
      expect(isBlacklisted).toBe(true);

      // Job should go to Node2
      const result1 = await sdk.submitJobWithNegotiation({
        prompt: "Avoiding blacklisted node",
        modelId: "llama-3.2-1b-instruct",
        maxTokens: 50,
      });

      expect(result1.selectedNode).toBe("12D3KooWNode2");

      // Wait for blacklist to expire
      await new Promise((resolve) => setTimeout(resolve, 1100));

      // Node1 should be available again
      const isStillBlacklisted = await sdk.isNodeBlacklisted("12D3KooWNode1");
      expect(isStillBlacklisted).toBe(false);

      // Record successful job for Node1
      sdk.recordJobOutcome("12D3KooWNode1", true, 1000);

      // Future jobs might use Node1 again
      const nodes = await sdk.discoverNodes({
        modelId: "llama-3.2-1b-instruct",
      });

      expect(nodes.some((n) => n.peerId === "12D3KooWNode1")).toBe(true);
    });

    it("should provide comprehensive system health report", async () => {
      sdk = new FabstirSDK({
        mode: "production",
        p2pConfig: {
          bootstrapNodes: ["/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWBootstrap"],
        },
        enableRecoveryReports: true,
      });

      await sdk.connect(mockProvider);

      // Simulate various operations
      await sdk.discoverNodes({ modelId: "llama-3.2-1b-instruct" });

      // Submit successful job
      const job1 = await sdk.submitJobWithNegotiation({
        prompt: "Successful job",
        modelId: "llama-3.2-1b-instruct",
        maxTokens: 50,
      });
      sdk.recordJobOutcome("12D3KooWNode1", true, 1500);

      // Simulate failure and recovery
      sdk.recordNodeFailure("12D3KooWNode2", "Connection lost");
      sdk.recordJobOutcome("12D3KooWNode2", false, 0);

      // Get system health report
      const healthReport = await sdk.getSystemHealthReport();

      expect(healthReport).toMatchObject({
        timestamp: expect.any(Number),
        uptime: expect.any(Number),
        mode: "production",
        p2pHealth: {
          connected: true,
          peerCount: expect.any(Number),
          bootstrapNodes: expect.any(Array),
        },
        nodeHealth: {
          totalNodes: expect.any(Number),
          healthyNodes: expect.any(Number),
          blacklistedNodes: expect.any(Array),
          averageReliability: expect.any(Number),
        },
        jobMetrics: {
          totalJobs: expect.any(Number),
          successfulJobs: expect.any(Number),
          failedJobs: expect.any(Number),
          averageProcessingTime: expect.any(Number),
        },
        recommendations: expect.any(Array),
      });

      // Record final performance summary
      performanceMetrics.operations.push({
        operation: "system_health_check",
        healthReport,
        timestamp: Date.now(),
      });
    });
  });

  // After all tests, log performance summary
  afterAll(() => {
    console.log("\n=== Integration Test Performance Summary ===");
    console.log(
      `Total test duration: ${Date.now() - performanceMetrics.startTime}ms`
    );
    console.log(`Total operations: ${performanceMetrics.operations.length}`);

    performanceMetrics.operations.forEach((op) => {
      console.log(`\n${op.operation}:`, JSON.stringify(op, null, 2));
    });
  });
});

// Type definitions to be implemented
export interface PerformanceMetrics {
  startTime: number;
  operations: any[];
}

export interface ModeTransitionReport {
  fromMode: "mock" | "production";
  toMode: "mock" | "production";
  operation: string;
  duration: number;
  success: boolean;
  error?: string;
}

export interface SystemHealthReport {
  timestamp: number;
  uptime: number;
  mode: "mock" | "production";
  p2pHealth: {
    connected: boolean;
    peerCount: number;
    bootstrapNodes: string[];
    failedConnections?: number;
    successfulConnections?: number;
  };
  nodeHealth: {
    totalNodes: number;
    healthyNodes: number;
    blacklistedNodes: string[];
    averageReliability: number;
  };
  jobMetrics: {
    totalJobs: number;
    successfulJobs: number;
    failedJobs: number;
    averageProcessingTime: number;
  };
  recommendations: string[];
}
