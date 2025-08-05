# Result Verification Guide

This guide covers how to verify and validate AI computation results from the Fabstir marketplace, ensuring quality and correctness.

## Prerequisites

- Completed jobs to verify
- Understanding of expected outputs
- Access to job results (IPFS/on-chain)
- Basic knowledge of proof systems

## Verification Overview

```
Get Result → Check Completeness → Validate Format → Verify Quality → Check Proof → Accept/Dispute
     ↓              ↓                    ↓               ↓              ↓              ↓
  Retrieve      Not Empty          Parse JSON       Accuracy       EZKL Valid    Payment
```

## Step 1: Retrieving Results

### Basic Result Retrieval
```javascript
const { ethers } = require("ethers");
const IPFS = require("ipfs-http-client");

class ResultRetriever {
    constructor(marketplaceAddress, ipfsGateway = "https://ipfs.io/ipfs/") {
        this.marketplace = new ethers.Contract(marketplaceAddress, ABI, provider);
        this.ipfsGateway = ipfsGateway;
        this.ipfs = IPFS.create({ url: 'http://localhost:5001' });
    }
    
    async getJobResult(jobId) {
        // Get job details from blockchain
        const job = await this.marketplace.getJob(jobId);
        
        if (job.status !== 2) { // Not completed
            throw new Error(`Job ${jobId} not completed. Status: ${job.status}`);
        }
        
        const resultCID = job.resultHash;
        console.log(`Retrieving result from IPFS: ${resultCID}`);
        
        // Retrieve from IPFS
        try {
            // Try local IPFS first
            const chunks = [];
            for await (const chunk of this.ipfs.cat(resultCID)) {
                chunks.push(chunk);
            }
            return Buffer.concat(chunks).toString();
        } catch (error) {
            // Fallback to public gateway
            console.log("Falling back to public gateway...");
            const response = await fetch(`${this.ipfsGateway}${resultCID}`);
            return await response.text();
        }
    }
    
    async getResultWithMetadata(jobId) {
        const result = await this.getJobResult(jobId);
        const job = await this.marketplace.getJob(jobId);
        
        return {
            jobId,
            result,
            resultCID: job.resultHash,
            completedAt: job.completedAt,
            assignedHost: job.assignedHost,
            modelUsed: job.modelId,
            payment: ethers.formatEther(job.payment)
        };
    }
}
```

### Batch Result Retrieval
```javascript
class BatchResultRetriever {
    async getMultipleResults(jobIds) {
        const results = await Promise.allSettled(
            jobIds.map(id => this.getResultWithMetadata(id))
        );
        
        const successful = [];
        const failed = [];
        
        results.forEach((result, index) => {
            if (result.status === 'fulfilled') {
                successful.push(result.value);
            } else {
                failed.push({
                    jobId: jobIds[index],
                    error: result.reason.message
                });
            }
        });
        
        return { successful, failed };
    }
}
```

## Step 2: Format Validation

### JSON Result Validation
```javascript
class ResultValidator {
    validateFormat(result, expectedFormat) {
        switch (expectedFormat) {
            case 'json':
                return this.validateJSON(result);
            case 'text':
                return this.validateText(result);
            case 'markdown':
                return this.validateMarkdown(result);
            case 'code':
                return this.validateCode(result);
            case 'image':
                return this.validateImage(result);
            default:
                return { valid: true };
        }
    }
    
    validateJSON(result) {
        try {
            const parsed = JSON.parse(result);
            return {
                valid: true,
                parsed,
                structure: this.analyzeJSONStructure(parsed)
            };
        } catch (error) {
            return {
                valid: false,
                error: error.message,
                position: this.findJSONError(result)
            };
        }
    }
    
    analyzeJSONStructure(obj) {
        const structure = {
            type: typeof obj,
            keys: [],
            depth: 0
        };
        
        if (typeof obj === 'object' && obj !== null) {
            structure.keys = Object.keys(obj);
            structure.depth = this.getMaxDepth(obj);
        }
        
        return structure;
    }
    
    validateText(result) {
        const validation = {
            valid: true,
            length: result.length,
            wordCount: result.split(/\s+/).length,
            language: this.detectLanguage(result),
            encoding: this.detectEncoding(result)
        };
        
        // Check for common issues
        if (result.length === 0) {
            validation.valid = false;
            validation.error = "Empty result";
        }
        
        if (result.includes('\0')) {
            validation.valid = false;
            validation.error = "Contains null bytes";
        }
        
        return validation;
    }
    
    validateCode(result) {
        const validation = {
            valid: true,
            language: this.detectProgrammingLanguage(result),
            syntax: null,
            hasErrors: false
        };
        
        // Basic syntax validation
        try {
            if (validation.language === 'javascript') {
                new Function(result); // Basic JS syntax check
            }
            validation.syntax = 'valid';
        } catch (error) {
            validation.syntax = 'invalid';
            validation.hasErrors = true;
            validation.error = error.message;
        }
        
        return validation;
    }
}
```

### Schema Validation
```javascript
const Ajv = require('ajv');

class SchemaValidator {
    constructor() {
        this.ajv = new Ajv({ allErrors: true });
    }
    
    validateAgainstSchema(result, schema) {
        const validate = this.ajv.compile(schema);
        const valid = validate(result);
        
        return {
            valid,
            errors: validate.errors,
            formattedErrors: this.formatErrors(validate.errors)
        };
    }
    
    // Common schemas
    static schemas = {
        summary: {
            type: "object",
            required: ["title", "summary", "keyPoints"],
            properties: {
                title: { type: "string", minLength: 1 },
                summary: { type: "string", minLength: 50 },
                keyPoints: {
                    type: "array",
                    items: { type: "string" },
                    minItems: 3
                }
            }
        },
        
        analysis: {
            type: "object",
            required: ["analysis", "confidence", "reasoning"],
            properties: {
                analysis: { type: "string" },
                confidence: { type: "number", minimum: 0, maximum: 1 },
                reasoning: { type: "array", items: { type: "string" } },
                evidence: { type: "array" }
            }
        },
        
        code: {
            type: "object",
            required: ["code", "language", "explanation"],
            properties: {
                code: { type: "string" },
                language: { type: "string" },
                explanation: { type: "string" },
                dependencies: { type: "array", items: { type: "string" } }
            }
        }
    };
}
```

## Step 3: Quality Verification

### Content Quality Checks
```javascript
class QualityChecker {
    async checkQuality(result, originalPrompt, expectedQuality) {
        const checks = {
            relevance: await this.checkRelevance(result, originalPrompt),
            completeness: this.checkCompleteness(result, expectedQuality),
            accuracy: await this.checkAccuracy(result),
            coherence: this.checkCoherence(result),
            originality: await this.checkOriginality(result)
        };
        
        const overallScore = this.calculateQualityScore(checks);
        
        return {
            score: overallScore,
            checks,
            passed: overallScore >= expectedQuality.minScore,
            recommendations: this.getRecommendations(checks)
        };
    }
    
    async checkRelevance(result, prompt) {
        // Check if result addresses the prompt
        const keywords = this.extractKeywords(prompt);
        const resultKeywords = this.extractKeywords(result);
        
        const overlap = this.calculateOverlap(keywords, resultKeywords);
        const semantic = await this.semanticSimilarity(prompt, result);
        
        return {
            score: (overlap + semantic) / 2,
            keywordMatch: overlap,
            semanticMatch: semantic
        };
    }
    
    checkCompleteness(result, expectations) {
        const checks = {
            hasAllSections: true,
            meetsLengthRequirement: true,
            addressesAllPoints: true
        };
        
        // Length check
        if (expectations.minLength) {
            checks.meetsLengthRequirement = result.length >= expectations.minLength;
        }
        
        // Required sections
        if (expectations.requiredSections) {
            for (const section of expectations.requiredSections) {
                if (!result.toLowerCase().includes(section.toLowerCase())) {
                    checks.hasAllSections = false;
                    break;
                }
            }
        }
        
        return {
            score: Object.values(checks).filter(v => v).length / Object.keys(checks).length,
            details: checks
        };
    }
    
    checkCoherence(result) {
        // Check logical flow and consistency
        const sentences = result.split(/[.!?]+/);
        let coherenceScore = 1.0;
        
        // Check for repetition
        const uniqueSentences = new Set(sentences.map(s => s.trim().toLowerCase()));
        const repetitionRatio = uniqueSentences.size / sentences.length;
        coherenceScore *= repetitionRatio;
        
        // Check for logical connectors
        const connectors = ['therefore', 'however', 'moreover', 'furthermore', 'consequently'];
        const hasConnectors = connectors.some(c => result.toLowerCase().includes(c));
        if (hasConnectors) coherenceScore *= 1.1;
        
        return {
            score: Math.min(1, coherenceScore),
            repetitionRatio,
            hasLogicalFlow: hasConnectors
        };
    }
}
```

### Automated Quality Scoring
```javascript
class AutomatedQualityScorer {
    async scoreResult(result, jobType) {
        const scorers = {
            'text_generation': this.scoreTextGeneration,
            'code_generation': this.scoreCodeGeneration,
            'data_analysis': this.scoreDataAnalysis,
            'translation': this.scoreTranslation,
            'summarization': this.scoreSummarization
        };
        
        const scorer = scorers[jobType] || this.genericScorer;
        return await scorer.call(this, result);
    }
    
    async scoreTextGeneration(result) {
        const metrics = {
            length: this.scoreLengthAppropriate(result, 500, 2000),
            readability: this.calculateReadabilityScore(result),
            grammar: await this.checkGrammar(result),
            structure: this.checkStructure(result),
            vocabulary: this.assessVocabulary(result)
        };
        
        const weights = {
            length: 0.1,
            readability: 0.3,
            grammar: 0.3,
            structure: 0.2,
            vocabulary: 0.1
        };
        
        const weightedScore = Object.entries(metrics).reduce((sum, [key, value]) => {
            return sum + (value * weights[key]);
        }, 0);
        
        return {
            overallScore: weightedScore,
            metrics,
            grade: this.scoreToGrade(weightedScore)
        };
    }
    
    scoreToGrade(score) {
        if (score >= 0.9) return 'A';
        if (score >= 0.8) return 'B';
        if (score >= 0.7) return 'C';
        if (score >= 0.6) return 'D';
        return 'F';
    }
}
```

## Step 4: Proof Verification

### EZKL Proof Validation
```javascript
class ProofVerifier {
    constructor(proofSystemAddress) {
        this.proofSystem = new ethers.Contract(proofSystemAddress, PROOF_ABI, provider);
    }
    
    async verifyProof(jobId) {
        try {
            // Get proof info from ProofSystem
            const proofInfo = await this.proofSystem.getProofInfo(jobId);
            
            if (proofInfo.status === 0) {
                return {
                    verified: false,
                    status: "NOT_SUBMITTED",
                    message: "No proof submitted for this job"
                };
            }
            
            if (proofInfo.status === 2) {
                return {
                    verified: true,
                    status: "VERIFIED",
                    verifiedAt: proofInfo.submissionTime,
                    prover: proofInfo.prover
                };
            }
            
            if (proofInfo.status === 3) {
                return {
                    verified: false,
                    status: "INVALID",
                    message: "Proof failed verification"
                };
            }
            
            // Status is SUBMITTED, needs verification
            return {
                verified: false,
                status: "PENDING_VERIFICATION",
                message: "Proof submitted but not yet verified"
            };
            
        } catch (error) {
            return {
                verified: false,
                status: "ERROR",
                message: error.message
            };
        }
    }
    
    async validateProofContent(proof) {
        // Validate proof structure
        const validation = {
            hasCorrectStructure: true,
            hasValidCommitments: true,
            matchesExpectedFormat: true,
            errors: []
        };
        
        // Check proof components
        if (!proof.modelCommitment || !proof.inputHash || !proof.outputHash) {
            validation.hasCorrectStructure = false;
            validation.errors.push("Missing required commitments");
        }
        
        // Validate commitment format (32 bytes)
        const isValidHash = (hash) => /^0x[a-fA-F0-9]{64}$/.test(hash);
        
        if (!isValidHash(proof.modelCommitment)) {
            validation.hasValidCommitments = false;
            validation.errors.push("Invalid model commitment format");
        }
        
        return validation;
    }
}
```

### Challenge System
```javascript
class ChallengeManager {
    constructor(proofSystemAddress, stakeToken) {
        this.proofSystem = new ethers.Contract(proofSystemAddress, PROOF_ABI, signer);
        this.stakeToken = new ethers.Contract(stakeToken, ERC20_ABI, signer);
    }
    
    async evaluateForChallenge(jobId, result) {
        const suspiciousIndicators = {
            resultTooShort: result.length < 10,
            containsError: result.includes("error") || result.includes("failed"),
            invalidFormat: !this.isValidFormat(result),
            mismatchedModel: await this.checkModelMismatch(jobId, result),
            duplicateResult: await this.checkForDuplicate(result)
        };
        
        const shouldChallenge = Object.values(suspiciousIndicators).some(v => v);
        
        return {
            shouldChallenge,
            indicators: suspiciousIndicators,
            confidence: this.calculateChallengeConfidence(suspiciousIndicators)
        };
    }
    
    async submitChallenge(jobId, evidence) {
        const stakeAmount = ethers.parseEther("10"); // 10 token stake
        
        // Approve stake
        const approveTx = await this.stakeToken.approve(
            this.proofSystem.address,
            stakeAmount
        );
        await approveTx.wait();
        
        // Prepare evidence
        const evidenceHash = ethers.id(JSON.stringify(evidence));
        
        // Submit challenge
        const challengeTx = await this.proofSystem.challengeProof(
            jobId,
            evidenceHash,
            stakeAmount
        );
        
        const receipt = await challengeTx.wait();
        
        // Extract challenge ID from events
        const event = receipt.logs.find(log => {
            try {
                return this.proofSystem.interface.parseLog(log).name === "ProofChallenged";
            } catch { return false; }
        });
        
        return {
            success: true,
            transactionHash: receipt.hash,
            challengeId: event.args.challengeId,
            deadline: Date.now() + (3 * 24 * 60 * 60 * 1000) // 3 days
        };
    }
}
```

## Step 5: Acceptance or Dispute

### Result Acceptance Flow
```javascript
class ResultAcceptance {
    async acceptResult(jobId, qualityScore) {
        // Record acceptance
        await this.recordAcceptance(jobId, {
            timestamp: Date.now(),
            qualityScore,
            accepted: true
        });
        
        // Optionally rate the host
        if (qualityScore > 0.8) {
            await this.rateHost(jobId, 5, "Excellent work!");
        } else if (qualityScore > 0.6) {
            await this.rateHost(jobId, 4, "Good job");
        } else {
            await this.rateHost(jobId, 3, "Acceptable");
        }
        
        return {
            status: "ACCEPTED",
            message: "Result accepted and host rated"
        };
    }
    
    async rateHost(jobId, rating, feedback) {
        const reputationSystem = new ethers.Contract(
            REPUTATION_SYSTEM_ADDRESS,
            REPUTATION_ABI,
            signer
        );
        
        const tx = await reputationSystem.rateHost(
            hostAddress,
            jobId,
            rating,
            feedback
        );
        
        await tx.wait();
        console.log(`Rated host ${rating}/5 for job ${jobId}`);
    }
}
```

### Dispute Process
```javascript
class DisputeManager {
    async initiateDispute(jobId, reason, evidence) {
        const marketplace = new ethers.Contract(MARKETPLACE_ADDRESS, ABI, signer);
        
        // Compile dispute data
        const disputeData = {
            jobId,
            reason,
            evidence,
            timestamp: Date.now(),
            expectedResult: evidence.expectedResult,
            actualResult: evidence.actualResult,
            qualityIssues: evidence.qualityIssues
        };
        
        // Submit dispute
        const tx = await marketplace.disputeResult(
            jobId,
            JSON.stringify(disputeData)
        );
        
        await tx.wait();
        
        // Upload detailed evidence to IPFS
        const evidenceCID = await this.uploadEvidence(disputeData);
        
        return {
            status: "DISPUTE_INITIATED",
            evidenceCID,
            nextSteps: [
                "Wait for arbiter review",
                "Provide additional evidence if requested",
                "Participate in resolution process"
            ]
        };
    }
}
```

## Verification Automation

### Automated Verification Pipeline
```javascript
class AutomatedVerificationPipeline {
    constructor(config) {
        this.config = config;
        this.validators = [];
        this.scorers = [];
    }
    
    async verifyResult(jobId) {
        const stages = [
            { name: "retrieval", fn: this.retrieveResult },
            { name: "format", fn: this.validateFormat },
            { name: "quality", fn: this.checkQuality },
            { name: "proof", fn: this.verifyProof },
            { name: "plagiarism", fn: this.checkPlagiarism },
            { name: "decision", fn: this.makeDecision }
        ];
        
        const results = {};
        let shouldContinue = true;
        
        for (const stage of stages) {
            if (!shouldContinue) break;
            
            try {
                results[stage.name] = await stage.fn.call(this, jobId, results);
                
                if (results[stage.name].critical && !results[stage.name].passed) {
                    shouldContinue = false;
                }
            } catch (error) {
                results[stage.name] = {
                    passed: false,
                    error: error.message
                };
                shouldContinue = false;
            }
        }
        
        return this.compileFinalReport(results);
    }
    
    compileFinalReport(results) {
        const report = {
            timestamp: new Date().toISOString(),
            overallStatus: this.determineOverallStatus(results),
            stages: results,
            score: this.calculateOverallScore(results),
            recommendation: this.getRecommendation(results)
        };
        
        return report;
    }
}
```

## Common Issues & Solutions

### Issue: Result Retrieved but Empty
```javascript
// Solution: Implement retry with fallback
async function robustResultRetrieval(jobId, maxRetries = 3) {
    for (let i = 0; i < maxRetries; i++) {
        const result = await getJobResult(jobId);
        
        if (result && result.length > 0) {
            return result;
        }
        
        // Wait before retry
        await new Promise(resolve => setTimeout(resolve, 2000 * (i + 1)));
    }
    
    throw new Error("Failed to retrieve non-empty result");
}
```

### Issue: JSON Parse Errors
```javascript
// Solution: Flexible parsing
function flexibleJSONParse(text) {
    // Try standard parse
    try {
        return JSON.parse(text);
    } catch (e1) {
        // Try removing common issues
        try {
            const cleaned = text
                .replace(/[\u0000-\u001F]+/g, '') // Remove control characters
                .replace(/,\s*}/, '}')             // Remove trailing commas
                .replace(/,\s*\]/, ']');           // Remove trailing commas in arrays
            return JSON.parse(cleaned);
        } catch (e2) {
            // Try extracting JSON from text
            const jsonMatch = text.match(/\{[\s\S]*\}/);
            if (jsonMatch) {
                try {
                    return JSON.parse(jsonMatch[0]);
                } catch (e3) {
                    throw new Error("Invalid JSON format");
                }
            }
        }
    }
}
```

## Best Practices

### 1. Set Clear Expectations
```javascript
const jobExpectations = {
    format: "json",
    schema: SchemaValidator.schemas.analysis,
    minQualityScore: 0.8,
    requiredSections: ["summary", "analysis", "recommendations"],
    maxProcessingTime: 300 // seconds
};
```

### 2. Implement Comprehensive Checks
```javascript
const verificationChecklist = [
    "Result retrieved successfully",
    "Format matches specification",
    "Content is relevant to prompt",
    "Quality meets standards",
    "Proof is valid",
    "No plagiarism detected",
    "Result delivered on time"
];
```

### 3. Document Issues
```javascript
function documentVerificationIssue(jobId, issue) {
    const record = {
        jobId,
        timestamp: Date.now(),
        issue: {
            type: issue.type,
            severity: issue.severity,
            description: issue.description,
            evidence: issue.evidence
        },
        action: issue.requiresAction ? "DISPUTE" : "NOTE"
    };
    
    // Store for future reference
    saveVerificationRecord(record);
}
```

## Next Steps

1. **[SDK Usage](../developers/sdk-usage.md)** - Automate verification
2. **[Monitoring Setup](../advanced/monitoring-setup.md)** - Track job quality
3. **[Governance](../advanced/governance-participation.md)** - Improve standards

## Resources

- [Verification Best Practices](https://fabstir.com/docs/verification)
- [Quality Standards](https://fabstir.com/standards)
- [Dispute Resolution Guide](https://fabstir.com/disputes)
- [Community Support](https://discord.gg/fabstir-verification)

---

Having issues? Check our [Troubleshooting Guide](https://fabstir.com/troubleshoot) →